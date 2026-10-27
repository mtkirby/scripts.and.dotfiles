"""Tests for myawssgdiagrams.py."""

from __future__ import annotations

import csv
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import myawssgdiagrams as d  # noqa: E402

REGION_COLS = (
    "profile,account_id,region,vpc_id,vpc_name,cidr_blocks,is_default,owner_id,"
    "eni_count,contents,status"
).split(",")
SG_COLS = (
    "profile,account_id,region,vpc_id,group_id,group_name,group_description,"
    "group_owner_id,group_tags,attached_enis,public_enis,attached_kinds,rule_id,"
    "direction,protocol,from_port,to_port,source_type,source,rule_description,"
    "rule_tags,status"
).split(",")
PROD, MON, NET = "111111111111", "333333333333", "444444444444"


def write_csv(path: Path, cols: list[str], rows: list[list[str]]) -> Path:
    """Write rows as a fully quoted CSV, like jq's @csv."""
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, quoting=csv.QUOTE_ALL)
        writer.writerow(cols)
        writer.writerows(rows)
    return path


def sg_rows(group: list[str], rules: list[tuple[str, ...]]) -> list[list[str]]:
    """Rows for one group: its 12 group columns, then each 6-column rule."""
    if not rules:
        return [group + [""] * 9 + ["ok"]]
    return [
        group + [f"sgr-{group[4]}-{i}", *rule, "", "", "ok"]
        for i, rule in enumerate(rules)
    ]


@pytest.fixture
def regions_csv(tmp_path: Path) -> Path:
    """Two scanned accounts' VPCs, a shared VPC, and an error row."""
    return write_csv(
        tmp_path / "regions.csv",
        REGION_COLS,
        [
            [
                "prod",
                PROD,
                "us-east-1",
                "vpc-prod",
                'main, "core"',
                "10.0.0.0/16",
                "false",
                PROD,
                "4",
                "ELB:1 ec2:3",
                "ok",
            ],
            [
                "prod",
                PROD,
                "us-west-2",
                "vpc-def",
                "",
                "172.31.0.0/16",
                "true",
                PROD,
                "1",
                "ec2:1",
                "ok",
            ],
            [
                "mon",
                MON,
                "us-east-1",
                "vpc-mon",
                "",
                "10.30.0.0/16",
                "false",
                NET,
                "1",
                "ec2:1",
                "ok",
            ],
            ["prod", PROD, "eu-west-1", "", "", "", "", "", "", "", "error: denied"],
        ],
    )


@pytest.fixture
def secgroups_csv(tmp_path: Path) -> Path:
    """A web tier, a database, a bastion, an unused group and a monitor."""

    def grp(
        gid: str,
        name: str,
        enis: str,
        public: str,
        kinds: str,
        acct: str = PROD,
        vpc: str = "vpc-prod",
        profile: str = "prod",
        region: str = "us-east-1",
    ) -> list[str]:
        return [
            profile,
            acct,
            region,
            vpc,
            gid,
            name,
            "",
            acct,
            "",
            enis,
            public,
            kinds,
        ]

    rows = []
    rows += sg_rows(
        grp("sg-alb", "alb", "1", "1", "ELB:1"),
        [
            ("ingress", "tcp", "443", "443", "ipv4", "0.0.0.0/0"),
            ("egress", "all", "all", "all", "ipv4", "0.0.0.0/0"),
        ],
    )
    rows += sg_rows(
        grp("sg-app", "app", "2", "0", "ec2:2"),
        [
            ("ingress", "tcp", "8080", "8080", "security-group", "sg-alb"),
            (
                "ingress",
                "tcp",
                "9100",
                "9100",
                "security-group",
                f"sg-mon (account {MON})",
            ),
            ("ingress", "all", "all", "all", "security-group", "sg-app"),
            ("egress", "tcp", "5432", "5432", "security-group", "sg-db"),
        ],
    )
    rows += sg_rows(
        grp("sg-db", "db", "1", "0", "RDSNetworkInterface:1"),
        [
            ("ingress", "tcp", "5432", "5432", "security-group", "sg-app"),
            ("ingress", "tcp", "5432", "5432", "ipv4", "10.200.0.0/16"),
            ("ingress", "tcp", "5432", "5432", "ipv4", "203.0.113.9/32"),
            ("ingress", "tcp", "5432", "5432", "ipv4", "10.0.5.0/24"),
            ("ingress", "tcp", "5432", "5432", "ipv4", "10.30.1.0/24"),
            ("ingress", "tcp", "22", "22", "prefix-list", "pl-corp"),
        ],
    )
    rows += sg_rows(
        grp("sg-old", "launch-wizard-1", "0", "0", ""),
        [
            ("ingress", "tcp", "22", "22", "ipv4", "0.0.0.0/0"),
        ],
    )
    rows += sg_rows(
        grp("sg-dev", "default", "1", "1", "ec2:1", vpc="vpc-def", region="us-west-2"),
        [
            ("ingress", "tcp", "3389", "3389", "ipv6", "::/0"),
        ],
    )
    rows += sg_rows(
        grp(
            "sg-mon",
            "prometheus",
            "1",
            "0",
            "ec2:1",
            acct=MON,
            vpc="vpc-mon",
            profile="mon",
        ),
        [
            (
                "egress",
                "tcp",
                "9100",
                "9100",
                "security-group",
                f"sg-app (account {PROD})",
            ),
        ],
    )
    rows += sg_rows(
        grp("sg-spare", "spare", "0", "0", "", acct=MON, vpc="vpc-mon", profile="mon"),
        [],
    )
    rows.append(["prod", PROD, "eu-west-1", "vpc-x"] + [""] * 17 + ["error: denied"])
    return write_csv(tmp_path / "secgroups.csv", SG_COLS, rows)


@pytest.fixture
def vpcs(regions_csv: Path) -> list[d.Vpc]:
    """The fixture's VPCs."""
    return d.load_vpcs(regions_csv)


@pytest.fixture
def groups(secgroups_csv: Path) -> list[d.Group]:
    """The fixture's groups."""
    return d.load_groups(secgroups_csv)


def by_id(groups: list[d.Group]) -> dict[str, d.Group]:
    """Groups keyed by ID."""
    return {g.group_id: g for g in groups}


def rule(
    proto: str,
    lo: str,
    hi: str,
    source: str = "0.0.0.0/0",
    source_type: str = "ipv4",
    direction: str = "ingress",
) -> d.Rule:
    """A rule with just the fields that matter."""
    return d.Rule("sgr-1", direction, proto, lo, hi, source_type, source, "")


def labels_of(page: d.Page) -> list[str]:
    """Every cell's label on a page."""
    return [c.get("value", "") for c in page.cells]


def edges_of(page: d.Page) -> list[ET.Element]:
    """The page's arrows that connect two cells."""
    return [c for c in page.cells if c.get("edge") and c.get("source")]


# --------------------------------------------------------------------------
# Loading


def test_load_vpcs_skips_errors_and_parses_fields(vpcs: list[d.Vpc]) -> None:
    assert [v.vpc_id for v in vpcs] == ["vpc-prod", "vpc-def", "vpc-mon"]
    prod = vpcs[0]
    assert prod.name == 'main, "core"'
    assert prod.cidrs == ["10.0.0.0/16"]
    assert prod.eni_count == 4 and not prod.is_default
    assert vpcs[1].is_default
    assert vpcs[2].owner_id == NET


def test_load_groups_collects_rules_per_group(groups: list[d.Group]) -> None:
    g = by_id(groups)
    assert set(g) == {
        "sg-alb",
        "sg-app",
        "sg-db",
        "sg-old",
        "sg-dev",
        "sg-mon",
        "sg-spare",
    }
    assert len(g["sg-app"].rules) == 4
    assert g["sg-spare"].rules == []
    assert (g["sg-alb"].attached_enis, g["sg-alb"].public_enis) == (1, 1)


def test_int_treats_blanks_as_zero() -> None:
    assert d._int("") == 0
    assert d._int("7") == 7


# --------------------------------------------------------------------------
# Rules


@pytest.mark.parametrize(
    "proto, lo, hi, expected",
    [
        ("all", "all", "all", "all traffic"),
        ("tcp", "443", "443", "tcp 443"),
        ("tcp", "1024", "65535", "tcp 1024-65535"),
        ("udp", "all", "all", "udp all ports"),
        ("icmp", "all", "all", "icmp"),
        ("icmpv6", "128", "0", "icmpv6 type 128"),
    ],
)
def test_port_label(proto: str, lo: str, hi: str, expected: str) -> None:
    assert d.port_label(rule(proto, lo, hi)) == expected


@pytest.mark.parametrize(
    "proto, lo, hi, expected",
    [
        ("all", "all", "all", "high"),
        ("tcp", "all", "all", "high"),
        ("tcp", "22", "22", "high"),
        ("tcp", "0", "65535", "high"),
        ("tcp", "443", "443", "low"),
        ("tcp", "80", "80", "low"),
        ("tcp", "8080", "8080", "medium"),
        ("icmp", "all", "all", "low"),
        ("50", "all", "all", "medium"),
    ],
)
def test_rule_risk(proto: str, lo: str, hi: str, expected: str) -> None:
    assert d.rule_risk(rule(proto, lo, hi)) == expected


def test_is_internet_needs_ingress_from_anywhere() -> None:
    assert rule("tcp", "1", "1").is_internet
    assert rule("tcp", "1", "1", "::/0", "ipv6").is_internet
    assert not rule("tcp", "1", "1", direction="egress").is_internet
    assert not rule("tcp", "1", "1", "10.0.0.0/8").is_internet


def test_group_exposure_and_risk(groups: list[d.Group]) -> None:
    g = by_id(groups)
    assert (g["sg-alb"].exposure, g["sg-alb"].internet_risk) == ("exposed", "low")
    assert (g["sg-dev"].exposure, g["sg-dev"].internet_risk) == ("exposed", "high")
    assert g["sg-old"].exposure == "unused"
    assert g["sg-app"].exposure == "" and g["sg-app"].internet_risk == ""
    g["sg-old"].attached_enis = 1
    assert g["sg-old"].exposure == "open"


def test_parse_sg_ref() -> None:
    assert d.parse_sg_ref("sg-1") == ("sg-1", "")
    assert d.parse_sg_ref("sg-1 (account 222)") == ("sg-1", "222")


def test_join_labels_dedupes_and_limits() -> None:
    assert d.join_labels(["a", "b", "a"]) == "a, b"
    assert d.join_labels(["a", "b", "c"], limit=2) == "a, b, +1 more"


def test_plural_and_esc_and_safe_name() -> None:
    assert d.plural(1, "group") == "1 group"
    assert d.plural(2, "group") == "2 groups"
    assert d.esc("<a & b>") == "&lt;a &amp; b&gt;"
    assert d.safe_name("prod/admin role") == "prod_admin_role"
    assert d.safe_name("") == "_"


def test_within_and_network() -> None:
    net = d._network("10.0.5.0/24")
    assert d._within(net, ["10.0.0.0/16"])
    assert not d._within(net, ["10.1.0.0/16", "fd00::/8", "junk"])
    assert d._network("not a cidr") is None


@pytest.mark.parametrize(
    "source, source_type, kind",
    [
        ("0.0.0.0/0", "ipv4", None),
        ("10.0.5.0/24", "ipv4", None),  # inside its own VPC
        ("sg-1", "security-group", None),
        ("pl-1", "prefix-list", "prefix-list"),
        ("10.30.1.0/24", "ipv4", "aws"),
        ("10.200.0.0/16", "ipv4", "private"),
        ("203.0.113.9/32", "ipv4", "public"),
        ("fd12::/64", "ipv6", "private"),
    ],
)
def test_classify_source(
    source: str, source_type: str, kind: str | None, vpcs: list[d.Vpc]
) -> None:
    found = d.classify_source(
        rule("tcp", "1", "1", source, source_type), ["10.0.0.0/16"], vpcs
    )
    assert (found[0] if found else None) == kind


def test_classify_source_counts_overlapping_vpcs(vpcs: list[d.Vpc]) -> None:
    vpcs = vpcs + [
        d.Vpc("x", "9", "r", "vpc-9", "", ["10.30.0.0/16"], False, "9", 0, "")
    ]
    kind, label = d.classify_source(rule("tcp", "1", "1", "10.30.1.0/24"), [], vpcs)
    assert kind == "aws" and "inside 2 scanned VPCs" in label


# --------------------------------------------------------------------------
# Layout


def test_layered_layout_chain_gets_one_layer_each() -> None:
    layout = d.layered_layout(["a", "b", "c"], [("a", "b"), ("b", "c")])
    assert {n: p[0] for n, p in layout.positions.items()} == {"a": 0, "b": 1, "c": 2}
    assert layout.bends == {}
    assert layout.rows == 1


def test_layered_layout_reserves_rows_for_long_edges() -> None:
    edges = [("a", "b"), ("b", "c"), ("c", "d"), ("a", "d")]
    layout = d.layered_layout(["a", "b", "c", "d"], edges)
    bends = layout.bends[("a", "d")]
    assert [lay for lay, _ in bends] == [1, 2]
    # The placeholder never shares a row with a real node in its layer
    for lay, row in bends:
        assert all(p != (lay, row) for p in layout.positions.values())
    assert layout.rows == 2


def test_layered_layout_survives_cycles_and_self_loops() -> None:
    edges = [("a", "b"), ("b", "c"), ("c", "a"), ("b", "b")]
    layout = d.layered_layout(["a", "b", "c"], edges)
    assert sorted(p[0] for p in layout.positions.values()) == [0, 1, 2]


def test_layered_layout_orders_to_avoid_crossings() -> None:
    edges = [("a", "y"), ("b", "x")]
    layout = d.layered_layout(["a", "b", "x", "y"], edges)
    pos = layout.positions
    assert (pos["a"][1] < pos["b"][1]) == (pos["y"][1] < pos["x"][1])


def test_lanes_spread_around_centre() -> None:
    lanes = d.Lanes(step=10, spread=20)
    assert [lanes.take(100) for _ in range(6)] == [100, 110, 90, 120, 80, 100]
    assert lanes.take(500) == 500


def test_route_turns_only_in_lanes_and_labels_last_stretch() -> None:
    src, dst = d.Box(0, 0, 100, 50), d.Box(400, 100, 100, 50)
    link = d.Link("s", "t", "", "", lanes=[150, 350], vias=[200])
    points, label_at = d.route(src, dst, 0.5, 0.5, link)
    assert points == [(150, 25), (150, 200), (350, 200), (350, 125)]
    # Every segment is horizontal or vertical
    path = [(100, 25)] + points + [(400, 125)]
    assert all(a[0] == b[0] or a[1] == b[1] for a, b in zip(path, path[1:]))
    assert 0 < label_at < 1


def test_connect_spreads_arrows_on_a_shared_side() -> None:
    page = d.Page("p")
    boxes = {
        n: d.Box(0 if n == "a" else 300, y, 100, 50)
        for n, y in (("a", 0), ("b", 0), ("c", 200))
    }
    ids = {n: page.vertex(n, b.x, b.y, b.w, b.h, "") for n, b in boxes.items()}
    links = [d.Link("a", t, "", "", [200]) for t in ("b", "c")]
    d.connect(page, ids, boxes, links)
    exits = sorted(
        c.get("style").split("exitY=")[1].split(";")[0] for c in edges_of(page)
    )
    assert exits == ["0.333", "0.667"]


# --------------------------------------------------------------------------
# draw.io output


def test_page_cells_and_written_file(tmp_path: Path) -> None:
    page = d.Page("first")
    a = page.vertex("<b>a</b>", 0, 0, 10, 10, "s")
    b = page.vertex("b", 0, 0, 10, 10, "s")
    page.edge(a, b, "x", "e", points=[(1, 2)], label_at=0.5)
    page.line(0, 0, 5, 0, "endArrow=block;")
    out = tmp_path / "sub" / "f.drawio"
    d.write_drawio([page, d.Page("second")], out)
    root = ET.parse(out).getroot()
    assert [p.get("name") for p in root.iter("diagram")] == ["first", "second"]
    cells = root.find("diagram").iter("mxCell")
    ids = [c.get("id") for c in cells]
    assert len(ids) == len(set(ids)) == 6
    edge = next(c for c in root.iter("mxCell") if c.get("source"))
    assert edge.get("target") == b
    assert edge.find("mxGeometry").get("x") == "0.500"


def test_legend_draws_arrows_for_edge_styles() -> None:
    page = d.Page("p")
    bottom = page.legend(
        [(d.node_style(d.RED), "box"), (d.edge_style(d.DARK), "arrow")], 0, 0
    )
    assert bottom == 26 + 2 * 30
    assert sum(1 for c in page.cells if c.get("edge")) == 1


def test_group_label_and_style(groups: list[d.Group]) -> None:
    g = by_id(groups)
    assert "used by ELB:1 (1 public)" in d.group_label(g["sg-alb"])
    assert "<i>unused</i>" in d.group_label(g["sg-old"])
    assert "prod · us-east-1 · vpc-prod" in d.group_label(g["sg-app"], where=True)
    assert "strokeWidth=3" in d.group_style(g["sg-alb"])
    assert d.GREEN[0] in d.group_style(g["sg-alb"])
    assert "dashed=1" in d.group_style(g["sg-old"])
    assert d.BLUE[0] in d.group_style(g["sg-app"])


# --------------------------------------------------------------------------
# Map 1


def test_vpc_graph_nodes_and_flows(groups: list[d.Group]) -> None:
    members = [g for g in groups if g.vpc_id == "vpc-prod"]
    graph = d.vpc_graph(members, by_id(groups), "vpc-prod")
    assert graph.nodes[0] == "internet"
    assert "sg-mon" in graph.nodes  # group in another account
    assert graph.flows[("sg-alb", "sg-app")] == ["tcp 8080"]
    assert graph.flows[("sg-app", "sg-app")] == ["all traffic"]
    assert ("sg-app", "sg-db") in graph.egress
    assert graph.risks[("internet", "sg-old")] == "high"
    assert "account 333333333333" in graph.labels["sg-mon"]


def test_vpc_edges_skip_self_and_mark_egress(groups: list[d.Group]) -> None:
    members = [g for g in groups if g.vpc_id == "vpc-prod"]
    edges = d.vpc_edges(d.vpc_graph(members, by_id(groups), "vpc-prod"))
    assert ("sg-app", "sg-app") not in edges
    assert edges[("sg-app", "sg-db")][0] == "egress tcp 5432"
    assert d.GREEN[1] in edges[("internet", "sg-alb")][1]
    assert d.RED[1] in edges[("internet", "sg-old")][1]


def test_outside_label() -> None:
    known = d.Group("p", "1", "r", "vpc-2", "sg-9", "nine", "", "1", "", 0, 0, "")
    assert d.outside_label("sg-9", "", known, "vpc-1").endswith("in vpc-2")
    assert d.outside_label("sg-9", "5", None, "vpc-1") == "sg-9<br>account 5"
    assert d.outside_label("sg-9", "", None, "vpc-1").endswith("outside this VPC")


def test_build_connections_one_page_per_vpc(
    groups: list[d.Group], vpcs: list[d.Vpc]
) -> None:
    pages = d.build_connections(groups, vpcs)
    assert {p: len(v) for p, v in pages.items()} == {"prod": 2, "mon": 1}
    main = next(p for p in pages["prod"] if "main" in p.name)
    # Every group in the main VPC has an arrow; mon's spare group has none
    heading = "Groups with no group-to-group rules"
    assert not any(heading in t for t in labels_of(main))
    mon = labels_of(pages["mon"][0])
    assert any(heading in t for t in mon) and any("sg-spare" in t for t in mon)
    loops = [c for c in edges_of(main) if "loop=1" in c.get("style")]
    assert len(loops) == 1 and loops[0].get("source") == loops[0].get("target")
    # Routed arrows have their corner points
    routed = [c for c in edges_of(main) if "edgeStyle=none" in c.get("style")]
    assert routed and all(c.find("mxGeometry/Array") is not None for c in routed)


# --------------------------------------------------------------------------
# Maps 2 to 5


def test_build_exposure_only_internet_groups(groups: list[d.Group]) -> None:
    page = d.build_exposure(groups)
    texts = " ".join(labels_of(page))
    assert "sg-alb" in texts and "sg-old" in texts and "sg-dev" in texts
    assert "sg-app" not in texts
    assert len(edges_of(page)) == 3
    assert "3 groups allow" in texts


def test_build_exposure_with_nothing_open() -> None:
    page = d.build_exposure([])
    assert any("No security group allows" in t for t in labels_of(page))


def test_cross_account_links(groups: list[d.Group], vpcs: list[d.Vpc]) -> None:
    trust, shared = d.cross_account_links(groups, vpcs)
    assert set(trust) == {(MON, PROD)}
    assert trust[(MON, PROD)] == ["tcp 9100 prometheus → app"] * 2
    assert shared == {(NET, MON): ["vpc-mon (us-east-1)"]}


def test_account_link_label() -> None:
    label = d.account_link_label(["r1", "r1", "r2", "r3", "r4"], ["vpc-1 (x)"])
    lines = label.split("<br>")
    assert lines[0] == "5 rules:"
    assert lines[1:4] == ["r1", "r2", "r3"]
    assert lines[4] == "+1 more"
    assert lines[5] == "shares vpc-1 (x)"


def test_build_cross_account(groups: list[d.Group], vpcs: list[d.Vpc]) -> None:
    page = d.build_cross_account(groups, vpcs)
    texts = " ".join(labels_of(page))
    assert "not scanned" in texts and NET in texts
    assert len(edges_of(page)) == 2


def test_build_origins(groups: list[d.Group], vpcs: list[d.Vpc]) -> None:
    page = d.build_origins(groups, vpcs)
    texts = " ".join(labels_of(page))
    for source in ("10.200.0.0/16", "203.0.113.9/32", "10.30.1.0/24", "pl-corp"):
        assert source in texts
    assert "10.0.5.0/24" not in texts  # the group's own VPC
    assert len(edges_of(page)) == 4


@pytest.mark.parametrize(
    "setup, colour",
    [
        ({"sg-dev": None}, d.RED),
        ({"sg-alb": None}, d.GREEN),
        ({"sg-app": None}, d.BLUE),
        ({"sg-spare": None}, d.GREY),
    ],
)
def test_vpc_risk(groups: list[d.Group], setup: dict, colour: tuple) -> None:
    g = by_id(groups)
    assert d.vpc_risk([g[k] for k in setup])[0] == colour


def test_vpc_risk_open_but_not_public(groups: list[d.Group]) -> None:
    old = by_id(groups)["sg-old"]
    old.attached_enis = 1
    assert d.vpc_risk([old]) == (d.YELLOW, d.NOT_PUBLIC)


def test_vpc_summary_and_sizes(groups: list[d.Group], vpcs: list[d.Vpc]) -> None:
    label, colours = d.vpc_summary(vpcs[2], [by_id(groups)["sg-mon"]])
    assert f"shared from {NET}" in label and "1 group," in label
    assert colours == d.BLUE
    assert d.region_size(1) == (d.VPC_W + 2 * d.GAP, 28 + d.VPC_H + 2 * d.GAP)
    assert d.region_size(5)[1] == 28 + 2 * (d.VPC_H + d.GAP) + d.GAP


def test_build_footprint(groups: list[d.Group], vpcs: list[d.Vpc]) -> None:
    page = d.build_footprint(groups, vpcs)
    texts = " ".join(labels_of(page))
    assert "2 accounts, 2 regions, 3 VPCs" in texts
    assert "prod (111111111111)" in texts and "us-west-2" in texts


# --------------------------------------------------------------------------
# main


def test_main_writes_every_file(
    regions_csv: Path, secgroups_csv: Path, tmp_path: Path
) -> None:
    out = tmp_path / "out"
    assert d.main([str(regions_csv), str(secgroups_csv), str(out)]) == 0
    names = sorted(str(p.relative_to(out)) for p in out.rglob("*.drawio"))
    assert names == [
        "1-sg-connections/mon.drawio",
        "1-sg-connections/prod.drawio",
        "2-internet-exposure.drawio",
        "3-cross-account.drawio",
        "4-network-origins.drawio",
        "5-org-footprint.drawio",
    ]
    for path in out.rglob("*.drawio"):
        ET.parse(path)  # well-formed


def test_main_fails_without_groups(regions_csv: Path, tmp_path: Path) -> None:
    empty = write_csv(tmp_path / "empty.csv", SG_COLS, [])
    assert d.main([str(regions_csv), str(empty), str(tmp_path / "o")]) == 1


def test_main_fails_on_missing_file(tmp_path: Path) -> None:
    assert d.main([str(tmp_path / "no.csv"), str(tmp_path / "no.csv"), "o"]) == 1


# --------------------------------------------------------------------------
# Edge cases


def make_group(gid: str, vpc: str = "vpc-1", account: str = "1", **kw) -> d.Group:
    """A bare group for edge-case tests."""
    fields = dict(attached_enis=1, public_enis=0, attached_kinds="ec2:1")
    fields.update(kw)
    return d.Group("p", account, "r", vpc, gid, gid, "", account, "", **fields)


def test_parse_sg_ref_and_classify_odd_input() -> None:
    assert d.parse_sg_ref("two words") == ("two words", "")
    assert d.classify_source(rule("tcp", "1", "1", "junk"), [], []) is None


def test_open_group_is_dashed_in_its_risk_colour() -> None:
    g = make_group("sg-1")
    g.rules.append(rule("tcp", "8080", "8080"))
    assert g.exposure == "open"
    style = d.group_style(g)
    assert d.AMBER[0] in style and "dashed=1" in style


def test_cycle_between_groups_is_still_drawn() -> None:
    a, b = make_group("sg-a"), make_group("sg-b")
    a.rules.append(rule("tcp", "1", "1", "sg-b", "security-group"))
    b.rules.append(rule("tcp", "2", "2", "sg-a", "security-group"))
    page = d.build_connections([a, b], [])["p"][0]
    styles = [c.get("style") for c in edges_of(page)]
    assert len(styles) == 2
    assert sum(1 for s in styles if s.startswith(d.BACK_STYLE[:20])) == 1


def test_maps_3_and_4_say_when_there_is_nothing() -> None:
    lone = [make_group("sg-1")]
    assert any(
        "no VPC is shared" in t for t in labels_of(d.build_cross_account(lone, []))
    )
    assert any("No rule allows" in t for t in labels_of(d.build_origins(lone, [])))


def test_vpc_risk_amber_for_exposed_non_web_ports() -> None:
    g = make_group("sg-1", public_enis=1)
    g.rules.append(rule("tcp", "8080", "8080"))
    assert d.vpc_risk([g])[0] == d.AMBER


def test_footprint_wraps_accounts_onto_new_rows() -> None:
    vpcs = [
        d.Vpc(
            f"p{i}", str(i), "r", f"vpc-{i}", "", ["10.0.0.0/16"], False, str(i), 0, ""
        )
        for i in range(12)
    ]
    page = d.build_footprint([], vpcs)
    tops = {
        float(c.find("mxGeometry").get("y"))
        for c in page.cells
        if c.get("parent") == "1" and "swimlane" in (c.get("style") or "")
    }
    assert len(tops) > 1
