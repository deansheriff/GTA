"""Writes the four out-of-Lagos story regions (D-028) as map files for the 3D game:
   game/data/map/regions/{abeokuta,kano,delta,anambra}.json
Same format as data/map/lagos.json (cells of 4 m), plus "ground" (grass/sand/dirt), "region", and
"set_pieces" (fixed models: Olumo Rock, the city gates, the refinery). Run: python tools/make_regions.py
"""
import json, os

ROADS = {"expressway": {"width": 148, "speed": 1.0}, "main": {"width": 112, "speed": 0.85}, "street": {"width": 80, "speed": 0.6}}
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "data", "map", "regions")


def box(x0, y0, x1, y1):
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


def region(rid, name, size, ground, land, lagoon, nodes, roads, districts, landmarks, start, set_pieces, comment):
    inland = rid != "delta" # no sea round Abeokuta, Kano or the Anambra village: land to the horizon
    if inland:
        land = {"land": box(0, 0, size[0], size[1])}
    return {
        "_comment": comment, "region": rid, "name": name, "size": size, "ground": ground, "inland": inland,
        "land": land, "lagoon": lagoon, "road_classes": ROADS, "nodes": nodes, "roads": roads,
        "districts": districts, "landmarks": landmarks, "start": start, "set_pieces": set_pieces,
        "beach_props": {}, "beach_buildings": {},
    }


REGIONS = [
    region("abeokuta", "Abeokuta, Ogun State", [96, 72], "grass",
        {"land": box(2, 2, 94, 70)}, box(200, 200, 201, 201),
        {"gate_w": [6, 40], "town_c": [30, 40], "town_n": [30, 14], "town_s": [30, 62], "town_e": [54, 40],
         "market": [42, 52], "olumo": [66, 38], "shrine": [76, 48]},
        [{"id": "abeokuta-road", "class": "main", "nodes": ["gate_w", "town_c", "town_e", "olumo"]},
         {"id": "town-ns", "class": "street", "nodes": ["town_n", "town_c", "town_s"]},
         {"id": "itoku", "class": "street", "nodes": ["town_c", "market"]},
         {"id": "shrine-path", "class": "street", "nodes": ["olumo", "shrine"]}],
        [{"id": "abeokuta", "name": "Abeokuta", "center": [32, 38], "density": 0.75,
          "buildings": {"bungalow": 5, "two-storey": 2, "provision-store": 2, "canteen": 2},
          "props": {"mango": 3, "palm": 2, "kiosk": 2, "umbrella": 2}},
         {"id": "itoku", "name": "Itoku adire market", "center": [44, 54], "density": 0.8,
          "buildings": {"pos-shop": 3, "provision-store": 3}, "props": {"umbrella": 4, "orange-tray": 2}}],
        [{"id": "olumo-rock", "name": "Olumo Rock", "district": "abeokuta", "cell": [66, 32], "kind": "spot"},
         {"id": "fakunle-shrine", "name": "Baba Fakunle's shrine", "district": "abeokuta", "cell": [76, 50], "kind": "bungalow"},
         {"id": "itoku-market", "name": "Itoku adire market", "district": "itoku", "cell": [44, 50], "kind": "market"}],
        {"player": [8, 42], "danfo": [8, 40]},
        [{"model": "free:mountain", "cell": [68, 26], "size": 46.0},
         {"model": "free:rock_large", "cell": [60, 30], "size": 9.0},
         {"model": "free:rock_large", "cell": [74, 34], "size": 7.0},
         {"model": "free:rock_large", "cell": [62, 22], "size": 11.0}],
        "Abeokuta: the town, Itoku's adire market, Olumo Rock and Baba Fakunle's shrine below it (Act II, M11)."),

    region("kano", "Kano", [96, 72], "sand",
        {"land": box(2, 2, 94, 70)}, box(200, 200, 201, 201),
        {"gate": [18, 36], "old_city": [36, 36], "palace": [36, 22], "durbar": [54, 36], "truck_park": [70, 52],
         "airstrip_w": [74, 20], "airstrip_e": [92, 20], "south": [36, 62]},
        [{"id": "kano-main", "class": "main", "nodes": ["gate", "old_city", "durbar", "truck_park"]},
         {"id": "palace-road", "class": "street", "nodes": ["old_city", "palace"]},
         {"id": "airstrip-road", "class": "main", "nodes": ["durbar", "airstrip_w", "airstrip_e"]},
         {"id": "kano-south", "class": "street", "nodes": ["old_city", "south"]}],
        [{"id": "kano-old-city", "name": "Kano old city", "center": [34, 40], "density": 0.85,
          "buildings": {"bungalow": 6, "canteen": 2, "provision-store": 2}, "props": {"tyres": 2, "kiosk": 2, "drum-chairs": 2}},
         {"id": "truck-park", "name": "Kano truck park", "center": [70, 54], "density": 0.5,
          "buildings": {"canteen": 2, "pos-shop": 1}, "props": {"tyres": 3, "generator": 2}}],
        [{"id": "kano-gate", "name": "Kofar Mata gate", "district": "kano-old-city", "cell": [18, 33], "kind": "spot"},
         {"id": "emir-palace", "name": "Emir's palace", "district": "kano-old-city", "cell": [36, 18], "kind": "two-storey"},
         {"id": "durbar-ground", "name": "Durbar ground", "district": "kano-old-city", "cell": [54, 32], "kind": "spot"},
         {"id": "kano-truck-park", "name": "Truck park", "district": "truck-park", "cell": [70, 48], "kind": "park"},
         {"id": "kano-airstrip", "name": "Private airstrip", "district": "truck-park", "cell": [88, 18], "kind": "spot"}],
        {"player": [12, 38], "danfo": [12, 36]},
        [{"model": "gate", "cell": [18, 36], "size": 14.0, "yaw": 0},
         {"model": "free:tent", "cell": [56, 28], "size": 5.0}, {"model": "free:tent", "cell": [60, 30], "size": 5.0},
         {"model": "free:gazebo", "cell": [52, 28], "size": 6.0}],
        "Kano during Sallah: the old city gate, the emir's palace, the Durbar ground, the truck park and the airstrip (Act III, M16)."),

    region("delta", "Niger Delta creeks", [96, 72], "grass",
        {"okoroba": [[8, 8], [30, 6], [34, 22], [22, 30], [6, 24]],
         "refinery": [[52, 34], [76, 30], [82, 46], [70, 56], [50, 50]],
         "camp": [[80, 6], [92, 8], [92, 22], [80, 20]]},
        box(0, 0, 96, 72),
        {"okoroba_c": [18, 16], "okoroba_s": [20, 26], "refinery_c": [66, 42], "refinery_w": [54, 42], "camp_c": [86, 14]},
        [{"id": "okoroba-path", "class": "street", "nodes": ["okoroba_c", "okoroba_s"]},
         {"id": "refinery-path", "class": "street", "nodes": ["refinery_w", "refinery_c"]}],
        [{"id": "okoroba", "name": "Okoroba", "center": [18, 16], "density": 0.8,
          "buildings": {"fisher-hut": 4, "bungalow": 2}, "props": {"canoe": 2, "nets": 2, "palm": 3, "fish-baskets": 2}},
         {"id": "refinery", "name": "Kpo-fire refinery", "center": [66, 42], "density": 0.4,
          "buildings": {"fisher-hut": 1}, "props": {"palm": 2}}],
        [{"id": "okoroba-jetty", "name": "Okoroba jetty", "district": "okoroba", "cell": [22, 28], "kind": "spot"},
         {"id": "kpo-refinery", "name": "Kpo-fire refinery", "district": "refinery", "cell": [66, 40], "kind": "spot"},
         {"id": "tonye-camp", "name": "General Tonye's camp", "district": "refinery", "cell": [86, 12], "kind": "spot"}],
        {"player": [18, 18], "danfo": [20, 18]},
        [{"model": "free:gas_tank", "cell": [64, 38], "size": 3.0}, {"model": "free:gas_tank", "cell": [68, 44], "size": 3.0},
         {"model": "free:barrel", "cell": [62, 44], "size": 1.0}, {"model": "free:barrel", "cell": [63, 45], "size": 1.0},
         {"model": "free:barrel", "cell": [70, 40], "size": 1.0}, {"model": "free:tent", "cell": [86, 14], "size": 5.0},
         {"model": "free:tent", "cell": [60, 46], "size": 5.0}],
        "The Niger Delta: mangrove creeks, Okoroba village, the kpo-fire refinery island and Tonye's camp (Act III, M17)."),

    region("anambra", "Obinna's village, Anambra", [96, 72], "grass",
        {"land": box(2, 2, 94, 70)}, box(200, 200, 201, 201),
        {"village_w": [6, 36], "square": [40, 36], "mansion": [62, 26], "farms": [40, 58], "helipad": [80, 30]},
        [{"id": "village-road", "class": "main", "nodes": ["village_w", "square", "mansion", "helipad"]},
         {"id": "farm-road", "class": "street", "nodes": ["square", "farms"]}],
        [{"id": "village", "name": "Obinna's village", "center": [36, 34], "density": 0.7,
          "buildings": {"bungalow": 6, "canteen": 1, "provision-store": 1}, "props": {"mango": 4, "palm": 3, "generator": 1}}],
        [{"id": "village-square", "name": "Village square", "district": "village", "cell": [40, 32], "kind": "spot"},
         {"id": "obinna-village-mansion", "name": "Chief Obinna's country house", "district": "village", "cell": [62, 22], "kind": "two-storey"},
         {"id": "yam-farms", "name": "Yam farms", "district": "village", "cell": [40, 58], "kind": "spot"},
         {"id": "village-helipad", "name": "Helipad", "district": "village", "cell": [80, 30], "kind": "spot"}],
        {"player": [8, 38], "danfo": [8, 36]},
        [{"model": "free:gazebo", "cell": [38, 30], "size": 7.0}, {"model": "free:gazebo", "cell": [44, 30], "size": 7.0},
         {"model": "yams", "cell": [40, 58], "size": 24.0}, {"model": "free:helicopter", "cell": [80, 30], "size": 10.0}],
        "Obinna's hometown in Anambra: the village square for the New Yam festival, his country house, yam farms (Act IV, M23)."),
]

os.makedirs(OUT, exist_ok=True)
for r in REGIONS:
    with open(os.path.join(OUT, r["region"] + ".json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(r, f, indent=1, ensure_ascii=False)
    print(r["region"], len(r["nodes"]), "nodes", len(r["landmarks"]), "landmarks")
