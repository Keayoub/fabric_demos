import json
from pathlib import Path
from types import ModuleType
import unittest
from unittest.mock import Mock


PATH = Path(__file__).resolve().parents[2] / "notebooks" / "nb_canadian_geo.ipynb"
geo = ModuleType("canadian_geo")
for cell in json.loads(PATH.read_text(encoding="utf-8"))["cells"]:
    if cell["cell_type"] == "code" and not "".join(cell["source"]).startswith("%pip "):
        exec(compile("".join(cell["source"]), str(PATH), "exec"), geo.__dict__)


class CanadianGeoTests(unittest.TestCase):
    def test_real_polygon_join_handles_boundary_outside_and_missing_coordinates(self):
        areas = [
            {"name": "West", "geom": {"type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]}},
            {"name": "East", "geom": {"type": "Polygon", "coordinates": [[[1, 0], [2, 0], [2, 1], [1, 1], [1, 0]]]}},
        ]
        parks = [
            {"parkid": 1, "name": "Inside", "googlemapdest": {"lat": 0.5, "lon": 0.5}, "hectare": 2},
            {"parkid": 2, "name": "Boundary", "googlemapdest": {"lat": 0.5, "lon": 1}},
            {"parkid": 3, "name": "Outside", "googlemapdest": {"lat": 3, "lon": 3}},
            {"parkid": 4, "name": "Missing"},
        ]
        rows, dimensions, rejected = geo.transform(parks, areas)
        self.assertEqual([r[2] for r in rows], ["west", "east", "unassigned"])
        self.assertEqual(rows[0][9], "POINT (0.5 0.5)")
        self.assertIn(("unassigned", "Unassigned by spatial join", None), dimensions)
        self.assertEqual(rejected, [{"park_id": 4, "reason": "missing_coordinates"}])
        self.assertAlmostEqual(geo.distance_km(49.2609, -123.1139), 0)

    def test_missing_source_page_fails_instead_of_truncating_the_snapshot(self):
        session = Mock()
        session.get.return_value.json.return_value = {"total_count": 2, "results": []}
        with self.assertRaisesRegex(ValueError, "pagination ended"):
            geo.fetch_records("parks", session)

    def test_duplicate_keys_are_rejected(self):
        parks = [{"parkid": 1, "name": "Park", "googlemapdest": {"lat": 1, "lon": 1}}] * 2
        with self.assertRaisesRegex(ValueError, "duplicate source park IDs"):
            geo.transform(parks, [])


if __name__ == "__main__":
    unittest.main()
