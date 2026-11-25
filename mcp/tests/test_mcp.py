import base64
import sys
import tempfile
import unittest
from pathlib import Path

from mcp import Client, StdioServerParameters
from mcp.types import ImageContent

from tests.test_library import add_revision, create_catalog, page


class MCPTests(unittest.IsolatedAsyncioTestCase):
    async def test_stdio_returns_text_and_handwriting_through_read_only_tools(self):
        with tempfile.TemporaryDirectory(prefix="nala-mcp-stdio-") as temporary:
            root = Path(temporary)
            writer = create_catalog(root)
            stroke = {
                "id": "s1",
                "tool": "pen",
                "argb": 4278190080,
                "width": 8,
                "points": [{"x": 30.0, "y": 40.0, "pressure": 1.0}],
            }
            add_revision(
                writer, "head", "synthetic",
                [page("first", "La derivación se relaciona con la pendiente", strokes=[stroke])],
            )
            writer.commit()
            writer.close()
            params = StdioServerParameters(
                command=sys.executable,
                args=["-m", "nala_mcp", "--data-root", str(root)],
                cwd=Path(__file__).resolve().parents[1],
            )
            async with Client(params, read_timeout_seconds=10) as client:
                tools = (await client.list_tools()).tools
                self.assertEqual(
                    {tool.name for tool in tools},
                    {"list_notebooks", "list_pages", "search", "fetch", "view_page"},
                )
                self.assertTrue(all(tool.annotations.read_only_hint for tool in tools))
                results = (await client.call_tool("search", {"query": "derivacion"})).structured_content
                self.assertEqual(results["results"][0]["citation"], "Álgebra, p. 1")
                args = {"notebook_id": "synthetic", "page_number": 1}
                fetched = (await client.call_tool("fetch", args)).structured_content
                self.assertIn("pendiente", fetched["text"])
                viewed = await client.call_tool("view_page", args)
                images = [content for content in viewed.content if isinstance(content, ImageContent)]
                self.assertFalse(viewed.is_error)
                self.assertEqual(len(images), 1)
                self.assertEqual(images[0].mime_type, "image/png")
                self.assertTrue(base64.b64decode(images[0].data).startswith(b"\x89PNG\r\n\x1a\n"))
                rejected = await client.call_tool("view_page", {**args, "page_number": 0})
                self.assertTrue(rejected.is_error)
