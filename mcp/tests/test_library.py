import hashlib
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from nala_mcp.library import Library, LibraryError


def page(page_id, text="", *, strokes=None):
    return {
        "id": page_id,
        "width": 595.28,
        "height": 841.89,
        "background": {"kind": "paper", "pattern": "grid"},
        "comments": [{"text": text}] if text else [],
        "strokes": strokes or [],
    }


def add_revision(db, revision, notebook, pages, *, parent=None, title="Álgebra"):
    book = {
        "schemaVersion": 1,
        "id": notebook,
        "title": title,
        "subject": "Matemática",
        "updatedAt": "2026-11-25T00:00:00.000Z",
        "pages": pages,
    }
    payload = json.dumps({
        "schemaVersion": 1,
        "id": revision,
        "parentId": parent,
        "notebook": book,
    })
    db.execute(
        "INSERT INTO revisions (id, document_id, parent_id, payload) VALUES (?, ?, ?, ?)",
        (revision, notebook, parent, payload),
    )


def create_catalog(root):
    db_path = root / "local" / "notes.db"
    db_path.parent.mkdir(parents=True)
    db = sqlite3.connect(db_path)
    db.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE revisions (
            id TEXT PRIMARY KEY, document_id TEXT, parent_id TEXT, payload TEXT
        );
        CREATE TABLE folders (id TEXT, parent_id TEXT, name TEXT, deleted INTEGER);
    """)
    return db


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nala-mcp-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.db = create_catalog(self.root)
        self.addCleanup(self.db.close)
        self.library = Library(self.root)

    def test_only_visible_heads_appear_even_when_a_late_edit_follows_deletion(self):
        add_revision(self.db, "old", "book", [page("p", "código previo")])
        add_revision(self.db, "now", "book", [page("p", "integración actual")], parent="old")
        add_revision(self.db, "origin", "removed", [page("removed", "integración eliminada")])
        add_revision(self.db, "nala-deleted-v1-abc", "removed", [page("removed")], parent="origin")
        add_revision(self.db, "late", "removed", [page("removed", "integración tardía")], parent="origin")
        self.db.commit()

        listing = self.library.list_notebooks()
        self.assertEqual([(item["notebook_id"], item["revision_id"]) for item in listing["items"]],
                         [("book", "now")])
        self.assertEqual([hit["page_id"] for hit in self.library.search("integracion")["results"]], ["p"])
        self.assertEqual(self.library.search("código")["results"], [])
        for book_id, revision in [("removed", "late"), ("book", "old")]:
            with self.assertRaises(LibraryError):
                self.library.fetch(book_id, 1, revision_id=revision)

    def test_reader_sees_committed_wal_and_keeps_the_database_read_only(self):
        add_revision(self.db, "first", "book", [page("p", "primero")])
        self.assertEqual(self.library.list_notebooks()["total"], 0)
        self.db.commit()
        self.assertEqual(self.library.list_notebooks()["total"], 1)
        with self.assertRaisesRegex(sqlite3.OperationalError, "readonly"):
            with self.library.open_database(self.root) as connection:
                connection.execute("DELETE FROM revisions")
        self.assertEqual(self.library.list_notebooks()["total"], 1)

    def test_catalog_is_resolved_at_each_query_like_the_linux_app(self):
        add_revision(self.db, "root-rev", "root-book", [page("p")])
        self.db.commit()
        account_id = hashlib.sha256(b"legacy-identifier").hexdigest()
        archive = create_catalog(self.root / "accounts" / account_id)
        self.addCleanup(archive.close)
        add_revision(archive, "account-rev", "account-book", [page("p")])
        archive.commit()

        (self.root / "active-account.json").write_text('{"id":"legacy-identifier"}')
        self.assertEqual(self.library.list_notebooks()["items"][0]["notebook_id"], "account-book")
        selection = self.root / "active-library.json"
        selection.write_text('{"catalog":null}')
        self.assertEqual(self.library.list_notebooks()["items"][0]["notebook_id"], "root-book")
        selection.write_text('{"catalog":"../other"}')
        with self.assertRaises(LibraryError):
            self.library.list_notebooks()

    def test_conflicts_require_explicit_revision_for_reading(self):
        add_revision(self.db, "base", "book", [page("p")])
        add_revision(self.db, "left", "book", [page("p", "límite lateral izquierdo")], parent="base")
        add_revision(self.db, "right", "book", [page("p", "límite lateral derecho")], parent="base")
        self.db.commit()
        self.assertTrue(all(item["has_conflict"] for item in self.library.list_notebooks()["items"]))
        with self.assertRaises(LibraryError):
            self.library.list_pages("book")
        results = self.library.search("lateral limite")["results"]
        self.assertEqual({item["revision_id"] for item in results}, {"left", "right"})
        self.assertIn("derecho", self.library.fetch("book", 1, revision_id="right")["text"])

    def test_pagination_keeps_the_notebook_and_page_citations(self):
        add_revision(self.db, "rev", "book", [page("a"), page("b", "integral " * 1000)])
        self.db.commit()
        pages = self.library.list_pages("book", offset=1, limit=1)
        self.assertEqual(pages["items"][0]["page_number"], 2)
        result = self.library.fetch("book", 2, revision_id="rev")
        self.assertEqual(result["page_id"], "b")
        self.assertEqual(result["citation"], "Álgebra, p. 2")
        self.assertEqual(len(result["text"]), result["next_offset"])
        rest = self.library.fetch("book", 2, revision_id="rev", offset=result["next_offset"])
        self.assertIsNone(rest["next_offset"])
        self.assertIn("integral", rest["text"])
