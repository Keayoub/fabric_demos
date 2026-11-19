import ast
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class NotebookTests(unittest.TestCase):
    def test_notebooks_have_valid_python_cells_and_bound_lakehouses(self):
        for path in (ROOT / "notebooks").glob("*.ipynb"):
            notebook = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(notebook["nbformat"], 4)
            self.assertEqual(notebook["metadata"]["language_info"]["name"], "python")
            binding = notebook["metadata"]["dependencies"]["lakehouse"]
            self.assertEqual(binding["default_lakehouse"], "{{ .LAKEHOUSE_ID }}")
            for cell in notebook["cells"]:
                self.assertTrue(all(line.endswith("\n") for line in cell["source"]), path.name)
                if cell["cell_type"] == "code":
                    python = "".join(line for line in cell["source"] if not line.startswith("%pip "))
                    ast.parse(python, filename=path.name)

    def test_spatial_fixture_has_closed_polygons_and_unique_contained_points(self):
        notebook = json.loads((ROOT / "notebooks" / "nb_spatial_showcase.ipynb").read_text())
        namespace = {}
        exec("".join(notebook["cells"][1]["source"]), namespace)
        source = "".join(notebook["cells"][2]["source"])
        tree = ast.parse(source[:source.index("zones = spark.createDataFrame")])
        tree.body = [
            node for node in tree.body
            if not (isinstance(node, ast.ImportFrom) and node.module == "pyspark.sql")
        ]
        exec(compile(tree, "spatial-fixture", "exec"), namespace)
        sites, zones, features = (namespace[name] for name in ("site_rows", "zone_rows", "features"))
        self.assertEqual((len(sites), len(zones)), (12, 4))
        self.assertEqual(len({site[0] for site in sites}), 12)
        for feature in features:
            ring = feature["geometry"]["coordinates"][0]
            self.assertEqual(ring[0], ring[-1])
            self.assertEqual(len(ring), 5)
        for site in sites:
            latitude, longitude = site[3:5]
            matches = [z for z in zones if z[2] <= longitude < z[4] and z[3] <= latitude < z[5]]
            self.assertEqual(len(matches), 1)
            self.assertEqual(site[6], f"POINT ({longitude} {latitude})")

    def test_map_categories_and_relational_keys_match_the_fixture(self):
        model = json.loads((ROOT / "infra" / "terraform" / "definitions" / "spatial-model.bim").read_text())
        sites, zones = model["model"]["tables"]
        columns = {c["name"]: c for c in sites["columns"]}
        self.assertEqual(columns["Latitude"]["dataCategory"], "Latitude")
        self.assertEqual(columns["Longitude"]["dataCategory"], "Longitude")
        self.assertEqual(columns["Latitude"]["summarizeBy"], "none")
        relation = model["model"]["relationships"][0]
        self.assertIn(relation["fromColumn"], columns)
        self.assertIn(relation["toColumn"], {c["name"] for c in zones["columns"]})
        self.assertEqual(sites["partitions"][0]["source"]["entityName"], "gold_spatial_sites")


if __name__ == "__main__":
    unittest.main()
