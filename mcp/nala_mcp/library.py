import hashlib
import json
import os
import re
import sqlite3
import unicodedata
from collections import Counter
from contextlib import closing, contextmanager
from dataclasses import dataclass
from pathlib import Path

from .page_text import page_text


# Mirrors SqliteNotebookRepository: a deletion hides the whole document, even
# if an offline client later adds a competing branch. Never fetch historical rows.
VISIBLE_HEAD = """
    NOT EXISTS (
        SELECT 1 FROM revisions d
        WHERE d.document_id = r.document_id AND d.id GLOB 'nala-deleted-v1-*'
    ) AND NOT EXISTS (
        SELECT 1 FROM revisions c
        WHERE c.document_id = r.document_id AND c.parent_id = r.id
    )
"""
TEXT_CHUNK = 8000


class LibraryError(ValueError):
    pass


def default_data_root() -> Path:
    configured = Path(os.environ.get("XDG_DATA_HOME") or "").expanduser()
    data_dir = configured if configured.is_absolute() else Path.home() / ".local/share"
    return data_dir / "com.felipe.apuntes"


def fold(text: str) -> str:
    return "".join(
        character for character in unicodedata.normalize("NFD", text.casefold())
        if not unicodedata.combining(character)
    )


def _slice(items: list, offset: int, limit: int) -> dict:
    end = offset + limit
    return {
        "items": items[offset:end],
        "total": len(items),
        "next_offset": end if end < len(items) else None,
    }


def _asset_dir(catalog: Path) -> Path:
    assets = catalog / "local" / "assets"
    if not assets.resolve().is_relative_to(catalog):
        raise LibraryError("La carpeta de recursos está fuera de la biblioteca activa.")
    return assets


@dataclass(frozen=True)
class Notebook:
    revision_id: str
    data: dict
    folder: tuple[str, ...]
    has_conflict: bool

    @property
    def pages(self) -> list[dict]:
        return self.data["pages"]

    def summary(self) -> dict:
        return {
            "notebook_id": self.data["id"],
            "revision_id": self.revision_id,
            "title": self.data["title"],
            "subject": self.data.get("subject", ""),
            "folder": list(self.folder),
            "page_count": len(self.pages),
            "has_conflict": self.has_conflict,
        }

    def reference(self, number: int) -> dict:
        page = self.pages[number - 1]
        title = self.data["title"]
        return {
            "notebook_id": self.data["id"],
            "revision_id": self.revision_id,
            "page_id": page["id"],
            "page_number": number,
            "title": title,
            "citation": f"{title}, p. {number}",
        }


class Library:
    def __init__(self, data_root: Path):
        self.data_root = data_root.expanduser().resolve()

    def _catalog(self) -> Path:
        selection = self.data_root / "active-library.json"
        legacy = self.data_root / "active-account.json"
        try:
            if selection.exists():
                catalog_id = json.loads(selection.read_text(encoding="utf-8"))["catalog"]
            elif legacy.exists():
                legacy_id = json.loads(legacy.read_text(encoding="utf-8"))["id"]
                catalog_id = hashlib.sha256(legacy_id.encode("utf-8")).hexdigest()
            else:
                catalog_id = None
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            raise LibraryError("La selección de biblioteca de Nala es inválida.") from error
        if catalog_id is None:
            return self.data_root
        if not isinstance(catalog_id, str) or not re.fullmatch(r"[0-9a-f]{64}", catalog_id):
            raise LibraryError("La selección de biblioteca de Nala es inválida.")
        catalog = (self.data_root / "accounts" / catalog_id).resolve()
        if not catalog.is_relative_to(self.data_root):
            raise LibraryError("La biblioteca activa está fuera de la carpeta de Nala.")
        return catalog

    @contextmanager
    def open_database(self, catalog: Path):
        database = (catalog / "local" / "notes.db").resolve()
        if not database.is_relative_to(catalog) or not database.is_file():
            raise LibraryError("No se encontró la base local de Nala. Revisá la biblioteca activa.")
        # Keep WAL visibility while forbidding every write to the notebook DB.
        with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=3)) as conn:
            conn.execute("PRAGMA query_only=ON")
            conn.execute("PRAGMA trusted_schema=OFF")
            yield conn

    def _snapshot(self, notebook_id: str | None = None) -> tuple[Path, list[Notebook]]:
        catalog = self._catalog()
        try:
            with self.open_database(catalog) as conn:
                conn.execute("BEGIN")
                condition = "" if notebook_id is None else "r.document_id = ? AND "
                params = () if notebook_id is None else (notebook_id,)
                rows = conn.execute(
                    f"SELECT r.id, r.document_id, r.payload FROM revisions r WHERE {condition}{VISIBLE_HEAD}",
                    params,
                ).fetchall()
                folders = {
                    id_: (parent, name) for id_, parent, name in conn.execute(
                        "SELECT id, parent_id, name FROM folders WHERE deleted = 0"
                    )
                }
            counts = Counter(doc_id for _, doc_id, _ in rows)
            books = []
            for revision_id, document_id, payload in rows:
                revision = json.loads(payload)
                data = revision["notebook"]
                if (
                    revision.get("schemaVersion") != 1
                    or data.get("schemaVersion") != 1
                    or revision["id"] != revision_id
                    or data["id"] != document_id
                ):
                    raise ValueError("unsupported revision")
                folder = _folder_names(data.get("folderId"), folders)
                books.append(Notebook(revision_id, data, folder, counts[document_id] > 1))
            books.sort(key=lambda book: (fold(book.data["title"]), book.data["id"], book.revision_id))
            return catalog, books
        except (OSError, sqlite3.Error, ValueError, KeyError, TypeError, AttributeError) as error:
            if isinstance(error, LibraryError):
                raise
            raise LibraryError("No se pudo leer la biblioteca local de Nala. Verificá su formato.") from error

    def _book(self, notebook_id: str, revision_id: str | None) -> tuple[Path, Notebook]:
        catalog, books = self._snapshot(notebook_id)
        if revision_id is not None:
            books = [book for book in books if book.revision_id == revision_id]
        if not books:
            raise LibraryError("El cuaderno o la revisión ya no están visibles. Volvé a listar los cuadernos.")
        if len(books) != 1:
            raise LibraryError("El cuaderno tiene versiones en conflicto. Indicá un revision_id visible.")
        return catalog, books[0]

    def list_notebooks(self, offset: int = 0, limit: int = 25) -> dict:
        _, books = self._snapshot()
        return _slice([book.summary() for book in books], offset, limit)

    def list_pages(
        self, notebook_id: str, revision_id: str | None = None,
        offset: int = 0, limit: int = 25,
    ) -> dict:
        _, book = self._book(notebook_id, revision_id)
        items = [
            {
                **book.reference(number),
                "has_handwriting": bool(page.get("strokes")),
                "background": page.get("background", {}).get("kind"),
            }
            for number, page in enumerate(book.pages, start=1)
        ]
        return _slice(items, offset, limit)

    def read_page(
        self, notebook_id: str, page_number: int, revision_id: str | None = None,
    ) -> tuple[dict, dict, Path]:
        catalog, book = self._book(notebook_id, revision_id)
        if not 1 <= page_number <= len(book.pages):
            raise LibraryError("Esa página no existe en la versión actual del cuaderno.")
        return book.reference(page_number), book.pages[page_number - 1], _asset_dir(catalog)

    def fetch(
        self, notebook_id: str, page_number: int, revision_id: str | None = None,
        offset: int = 0,
    ) -> dict:
        reference, page, assets = self.read_page(notebook_id, page_number, revision_id)
        data = page_text(page, assets)
        text = "\n\n".join(f"{label}\n{value}" for label, value in data.sections)
        end = offset + TEXT_CHUNK
        return {
            **reference,
            "text": text[offset:end],
            "next_offset": end if end < len(text) else None,
            "has_handwriting": bool(page.get("strokes")),
            "warnings": list(data.warnings),
        }

    def search(
        self, query: str, notebook_id: str | None = None,
        offset: int = 0, limit: int = 12,
    ) -> dict:
        terms = tuple(dict.fromkeys(re.findall(r"\w+", fold(query))))
        if not terms:
            raise LibraryError("Ingresá al menos una palabra para buscar.")
        catalog, books = self._snapshot(notebook_id)
        assets = _asset_dir(catalog)
        matches = []
        pages_with_warnings = 0
        pages_with_handwriting = 0
        for book in books:
            metadata = ("Cuaderno", " · ".join(
                (book.data["title"], book.data.get("subject", ""), *book.folder)
            ))
            for number, page in enumerate(book.pages, start=1):
                data = page_text(page, assets)
                pages_with_warnings += bool(data.warnings)
                pages_with_handwriting += bool(page.get("strokes"))
                match = _match(terms, metadata, data.sections, number == 1)
                if match is not None:
                    score, label, snippet = match
                    matches.append((score, {
                        **book.reference(number), "source": label, "snippet": snippet,
                    }))
        matches.sort(key=lambda entry: -entry[0])
        paged = _slice([result for _, result in matches], offset, limit)
        return {
            "results": paged["items"],
            "total": paged["total"],
            "next_offset": paged["next_offset"],
            "pages_with_handwriting": pages_with_handwriting,
            "pages_with_extraction_warnings": pages_with_warnings,
        }


def _folder_names(folder_id: str | None, folders: dict) -> tuple[str, ...]:
    names = []
    seen = set()
    while folder_id in folders and folder_id not in seen:
        seen.add(folder_id)
        folder_id, name = folders[folder_id]
        names.append(name)
    return tuple(reversed(names))


def _match(
    terms: tuple[str, ...], metadata: tuple[str, str],
    sections: tuple[tuple[str, str], ...], first_page: bool,
) -> tuple[int, str, str] | None:
    fields = [(*section, fold(section[1])) for section in (metadata, *sections)]
    if not all(any(term in value for _, _, value in fields) for term in terms):
        return None
    # Give a notebook-only match once, on its first page.
    candidates = fields if first_page else fields[1:]
    best = None
    for label, source, text in candidates:
        positions = [text.find(term) for term in terms if term in text]
        if not positions:
            continue
        score = len(positions) * 2 + (" ".join(terms) in text)
        if best is None or score > best[0]:
            anchor = min(positions)
            start = max(0, anchor - 65)
            end = min(len(source), start + 240)
            excerpt = " ".join(source[start:end].split())
            best = (score, label, ("…" if start else "") + excerpt + ("…" if end < len(source) else ""))
    return best
