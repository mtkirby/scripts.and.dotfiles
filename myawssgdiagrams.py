#!/usr/bin/env python3
"""Draw.io diagrams of AWS security groups across an organization.

Reads the CSVs from myawsgetregions.sh and myawsgetsecgroups.sh and writes:

    1-sg-connections/<profile>.drawio
        One page per VPC: its security groups, the group-to-group rules
        between them, and which groups the internet can reach.
    2-internet-exposure.drawio
        Every group that allows inbound traffic from 0.0.0.0/0 or ::/0,
        coloured by the ports it opens and whether anything public uses it.
    3-cross-account.drawio
        Accounts whose security groups allow traffic from groups in other
        accounts, and VPCs shared between accounts.
    4-network-origins.drawio
        The address ranges and prefix lists rules allow, other than the
        internet and the group's own VPC: on-premises, VPN, partner and other
        VPC ranges.
    5-org-footprint.drawio
        Account > region > VPC, each VPC with its group counts and a colour
        for its internet exposure.

Usage:
    myawsgetregions.sh profiles.txt > regions.csv
    myawsgetsecgroups.sh regions.csv > secgroups.csv
    myawssgdiagrams.py regions.csv secgroups.csv diagrams/

Open the files with draw.io (app or app.diagrams.net). Standard library only.
Arrows are routed here rather than by draw.io: they leave a box on the right,
enter the next on the left, and turn only in the gaps between columns, so
they never cross a box. Moving a box in draw.io keeps its arrows attached.
"""

from __future__ import annotations

import argparse
import csv
import html
import ipaddress
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

INTERNET = ("0.0.0.0/0", "::/0")

# Ports that should never be open to the internet: remote shells and desktops,
# Windows file sharing, databases, caches and admin APIs
RISKY_PORTS = {
    21: "FTP",
    22: "SSH",
    23: "Telnet",
    135: "RPC",
    137: "NetBIOS",
    138: "NetBIOS",
    139: "NetBIOS",
    445: "SMB",
    1433: "SQL Server",
    1521: "Oracle",
    2049: "NFS",
    2375: "Docker",
    2379: "etcd",
    3306: "MySQL",
    3389: "RDP",
    5432: "PostgreSQL",
    5900: "VNC",
    5984: "CouchDB",
    6379: "Redis",
    9200: "Elasticsearch",
    11211: "Memcached",
    27017: "MongoDB",
}
WEB_PORTS = {80, 443}
RISK_ORDER = {"low": 0, "medium": 1, "high": 2}

# fill, stroke
RED = ("#f8cecc", "#b85450")
AMBER = ("#ffe6cc", "#d79b00")
GREEN = ("#d5e8d4", "#82b366")
BLUE = ("#dae8fc", "#6c8ebf")
GREY = ("#f5f5f5", "#999999")
PURPLE = ("#e1d5e7", "#9673a6")
YELLOW = ("#fff2cc", "#d6b656")
RISK_COLOURS = {"high": RED, "medium": AMBER, "low": GREEN}
DARK = "#333333"

# Verdicts shared by the keys and map 5
NOT_PUBLIC = "allows the internet, but nothing public uses it"
IN_USE = "in use, not open to the internet"

PRIVATE_NETS = [
    ipaddress.ip_network(n)
    for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10")
] + [ipaddress.ip_network("fc00::/7")]


# --------------------------------------------------------------------------
# Data


@dataclass
class Vpc:
    """One VPC row from myawsgetregions.sh."""

    profile: str
    account_id: str
    region: str
    vpc_id: str
    name: str
    cidrs: list[str]
    is_default: bool
    owner_id: str
    eni_count: int
    contents: str


@dataclass
class Rule:
    """One security group rule from myawsgetsecgroups.sh."""

    rule_id: str
    direction: str
    protocol: str
    from_port: str
    to_port: str
    source_type: str
    source: str
    description: str

    @property
    def is_internet(self) -> bool:
        """True for an ingress rule from 0.0.0.0/0 or ::/0."""
        return self.direction == "ingress" and self.source in INTERNET


@dataclass
class Group:
    """A security group and its rules from myawsgetsecgroups.sh."""

    profile: str
    account_id: str
    region: str
    vpc_id: str
    group_id: str
    name: str
    description: str
    owner_id: str
    tags: str
    attached_enis: int
    public_enis: int
    attached_kinds: str
    rules: list[Rule] = field(default_factory=list)

    @property
    def internet_rules(self) -> list[Rule]:
        """The ingress rules that allow traffic from the internet."""
        return [r for r in self.rules if r.is_internet]

    @property
    def exposure(self) -> str:
        """How reachable the group's internet rules make it.

        "exposed": something with a public IP uses it.
        "open": it's in use, but nothing using it has a public IP.
        "unused": nothing uses it.
        "": it has no internet rules.
        """
        if not self.internet_rules:
            return ""
        if self.public_enis > 0:
            return "exposed"
        if self.attached_enis > 0:
            return "open"
        return "unused"

    @property
    def internet_risk(self) -> str:
        """The highest risk among the group's internet rules, or ""."""
        risks = [rule_risk(r) for r in self.internet_rules]
        return max(risks, key=RISK_ORDER.get) if risks else ""


def _int(value: str) -> int:
    """Parse a count column, treating blanks as 0."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def load_vpcs(path: Path) -> list[Vpc]:
    """Read the VPC rows of a myawsgetregions.sh CSV, skipping errors."""
    vpcs = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row.get("status") != "ok" or not row.get("vpc_id"):
                continue
            vpcs.append(
                Vpc(
                    profile=row["profile"],
                    account_id=row["account_id"],
                    region=row["region"],
                    vpc_id=row["vpc_id"],
                    name=row.get("vpc_name", ""),
                    cidrs=row.get("cidr_blocks", "").split(),
                    is_default=row.get("is_default") == "true",
                    owner_id=row.get("owner_id", ""),
                    eni_count=_int(row.get("eni_count", "")),
                    contents=row.get("contents", ""),
                )
            )
    return vpcs


def load_groups(path: Path) -> list[Group]:
    """Read a myawsgetsecgroups.sh CSV into groups, each with its rules."""
    groups: dict[tuple[str, str, str], Group] = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row.get("status") != "ok" or not row.get("group_id"):
                continue
            key = (row["account_id"], row["region"], row["group_id"])
            group = groups.get(key)
            if group is None:
                group = groups[key] = Group(
                    profile=row["profile"],
                    account_id=row["account_id"],
                    region=row["region"],
                    vpc_id=row["vpc_id"],
                    group_id=row["group_id"],
                    name=row.get("group_name", ""),
                    description=row.get("group_description", ""),
                    owner_id=row.get("group_owner_id", ""),
                    tags=row.get("group_tags", ""),
                    attached_enis=_int(row.get("attached_enis", "")),
                    public_enis=_int(row.get("public_enis", "")),
                    attached_kinds=row.get("attached_kinds", ""),
                )
            if row.get("rule_id"):
                group.rules.append(
                    Rule(
                        rule_id=row["rule_id"],
                        direction=row.get("direction", ""),
                        protocol=row.get("protocol", ""),
                        from_port=row.get("from_port", ""),
                        to_port=row.get("to_port", ""),
                        source_type=row.get("source_type", ""),
                        source=row.get("source", ""),
                        description=row.get("rule_description", ""),
                    )
                )
    return list(groups.values())


# --------------------------------------------------------------------------
# Rule helpers


def port_label(rule: Rule) -> str:
    """Short text for what a rule allows, e.g. "tcp 443" or "all traffic"."""
    proto = rule.protocol
    if proto == "all":
        return "all traffic"
    if proto in ("icmp", "icmpv6", "1", "58"):
        name = "icmpv6" if proto in ("icmpv6", "58") else "icmp"
        if rule.from_port in ("all", ""):
            return name
        return f"{name} type {rule.from_port}"
    if rule.from_port in ("all", ""):
        return f"{proto} all ports"
    if rule.from_port == rule.to_port:
        return f"{proto} {rule.from_port}"
    return f"{proto} {rule.from_port}-{rule.to_port}"


def rule_risk(rule: Rule) -> str:
    """Risk of a rule if its source were the internet: high, medium or low.

    High: all traffic, all ports, or a range that includes a risky port such as
    SSH, RDP or a database. Low: only HTTP/HTTPS, or ICMP. Medium: the rest.
    """
    proto = rule.protocol
    if proto == "all":
        return "high"
    if proto in ("icmp", "icmpv6", "1", "58"):
        return "low"
    if proto not in ("tcp", "udp", "6", "17"):
        return "medium"
    if rule.from_port in ("all", ""):
        return "high"
    lo, hi = _int(rule.from_port), _int(rule.to_port or rule.from_port)
    if any(lo <= port <= hi for port in RISKY_PORTS):
        return "high"
    if lo == hi and lo in WEB_PORTS:
        return "low"
    return "medium"


def parse_sg_ref(source: str) -> tuple[str, str]:
    """Split "sg-1 (account 222)" into ("sg-1", "222"); "sg-1" gives ("sg-1", "")."""
    m = re.match(r"(\S+)(?: \(account (\d+)\))?$", source.strip())
    if not m:
        return source, ""
    return m.group(1), m.group(2) or ""


def join_labels(labels: list[str], limit: int = 4) -> str:
    """Join distinct labels in order, showing at most `limit` and a "+N more"."""
    unique = list(dict.fromkeys(labels))
    shown = ", ".join(unique[:limit])
    if len(unique) > limit:
        shown += f", +{len(unique) - limit} more"
    return shown


def plural(count: int, word: str) -> str:
    """ "1 group", "2 groups"."""
    return f"{count} {word}{'' if count == 1 else 's'}"


def esc(text: str) -> str:
    """Escape text for an HTML label."""
    return html.escape(text, quote=False)


def _network(cidr: str) -> ipaddress.IPv4Network | ipaddress.IPv6Network | None:
    """Parse a CIDR, or None if it isn't one."""
    try:
        return ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return None


def _within(
    net: ipaddress.IPv4Network | ipaddress.IPv6Network, cidrs: list[str]
) -> bool:
    """True if network `net` lies inside any of `cidrs`."""
    for cidr in cidrs:
        outer = _network(cidr)
        if outer is not None and outer.version == net.version and net.subnet_of(outer):
            return True
    return False


def classify_source(
    rule: Rule, own_cidrs: list[str], vpcs: list[Vpc]
) -> tuple[str, str] | None:
    """Classify an address-range or prefix-list source for map 4.

    Returns (kind, label), or None for sources map 4 leaves out: the internet,
    the group's own VPC, and group references. kind is one of "prefix-list",
    "aws" (inside another scanned VPC), "private" (on-premises, VPN or peered)
    or "public" (a specific public range: offices, partners, vendors).
    """
    if rule.source_type == "prefix-list":
        return "prefix-list", f"{rule.source}<br>prefix list"
    if rule.source_type not in ("ipv4", "ipv6") or rule.source in INTERNET:
        return None
    net = _network(rule.source)
    if net is None:
        return None
    if _within(net, own_cidrs):
        return None
    matches = [v for v in vpcs if _within(net, v.cidrs)]
    if len(matches) == 1:
        v = matches[0]
        return "aws", f"{rule.source}<br>in {esc(v.profile)} {v.vpc_id}"
    if matches:
        return "aws", f"{rule.source}<br>inside {len(matches)} scanned VPCs"
    if any(net.version == p.version and net.subnet_of(p) for p in PRIVATE_NETS):
        return "private", f"{rule.source}<br>private: on-prem, VPN or peered"
    return "public", f"{rule.source}<br>public range"


# --------------------------------------------------------------------------
# Layout


@dataclass
class Layout:
    """Where layered_layout put things.

    positions: {node: (layer, row)}.
    bends: {(source, target): [(layer, row), ...]} for an edge that skips
        layers: the empty rows reserved for it in each layer it crosses.
    rows: the most rows any layer has, counting the reserved ones.
    """

    positions: dict[str, tuple[int, int]]
    bends: dict[tuple[str, str], list[tuple[int, int]]]
    rows: int


def _acyclic(nodes: list[str], edges: list[tuple[str, str]]) -> dict[str, list[str]]:
    """Successors of each node, minus self-loops, duplicates and cycle-closers.

    A depth-first search drops each edge that points back to a node still on
    its stack, which is exactly what makes the graph acyclic.
    """
    succ: dict[str, list[str]] = {n: [] for n in nodes}
    for a, b in edges:
        if a != b and a in succ and b in succ and b not in succ[a]:
            succ[a].append(b)
    dag: dict[str, list[str]] = {n: [] for n in nodes}
    state: dict[str, int] = {}  # 1 on the stack, 2 done
    for root in nodes:
        if root in state:
            continue
        state[root] = 1
        stack = [(root, iter(succ[root]))]
        while stack:
            node, children = stack[-1]
            child = next(children, None)
            if child is None:
                state[node] = 2
                stack.pop()
            elif state.get(child) != 1:
                dag[node].append(child)
                if child not in state:
                    state[child] = 1
                    stack.append((child, iter(succ[child])))
    return dag


def _longest_path_layers(nodes: list[str], dag: dict[str, list[str]]) -> dict[str, int]:
    """Each node's layer: the length of the longest path reaching it."""
    layer = dict.fromkeys(nodes, 0)
    waiting = dict.fromkeys(nodes, 0)
    for children in dag.values():
        for b in children:
            waiting[b] += 1
    ready = [n for n in nodes if waiting[n] == 0]
    while ready:
        node = ready.pop(0)
        for child in dag[node]:
            layer[child] = max(layer[child], layer[node] + 1)
            waiting[child] -= 1
            if waiting[child] == 0:
                ready.append(child)
    return layer


def _add_placeholders(
    dag: dict[str, list[str]], layer: dict[str, int]
) -> tuple[dict[str, list[str]], dict[tuple[str, str], list[str]]]:
    """Split edges that skip layers into chains through placeholder nodes.

    Adds the placeholders to `layer`. Returns the new successor lists and,
    for each edge that got placeholders, the chain of them in order.
    """
    succ: dict[str, list[str]] = {n: [] for n in dag}
    chains: dict[tuple[str, str], list[str]] = {}
    for a, children in dag.items():
        for b in children:
            chain = []
            prev = a
            for lay in range(layer[a] + 1, layer[b]):
                dummy = f"\0{len(layer)}"
                layer[dummy] = lay
                succ[dummy] = []
                succ[prev].append(dummy)
                chain.append(dummy)
                prev = dummy
            succ[prev].append(b)
            if chain:
                chains[(a, b)] = chain
    return succ, chains


def _order_layers(
    layers: dict[int, list[str]], succ: dict[str, list[str]], sweeps: int
) -> dict[str, int]:
    """Each node's row: layers sorted by the average row of their neighbours.

    Sweeps alternate left to right (by predecessors) and back (by successors).
    """
    pred: dict[str, list[str]] = {n: [] for n in succ}
    for a, children in succ.items():
        for b in children:
            pred[b].append(a)
    pos = {n: i for members in layers.values() for i, n in enumerate(members)}

    def reorder(members: list[str], neighbours: dict[str, list[str]]) -> None:
        def key(n: str) -> float:
            near = [pos[m] for m in neighbours[n]]
            return sum(near) / len(near) if near else pos[n]

        members.sort(key=key)
        for i, n in enumerate(members):
            pos[n] = i

    depth = max(layers, default=0)
    for _ in range(sweeps):
        for lay in range(1, depth + 1):
            reorder(layers[lay], pred)
        for lay in range(depth - 1, -1, -1):
            reorder(layers[lay], succ)
    return pos


def layered_layout(
    nodes: list[str], edges: list[tuple[str, str]], sweeps: int = 4
) -> Layout:
    """Place a directed graph in left-to-right layers (Sugiyama style).

    Cycles are broken by ignoring the edges a depth-first search finds pointing
    back; layers are the longest path from a source; an edge that skips layers
    gets a placeholder in each layer it crosses, so it has an empty row to pass
    through; and each layer is ordered by the average row of its neighbours
    (the barycenter heuristic) to cut down on crossings.
    """
    dag = _acyclic(nodes, edges)
    layer = _longest_path_layers(nodes, dag)
    succ, chains = _add_placeholders(dag, layer)
    layers: dict[int, list[str]] = defaultdict(list)
    for n in succ:  # nodes in input order, then placeholders
        layers[layer[n]].append(n)
    pos = _order_layers(layers, succ, sweeps)
    return Layout(
        positions={n: (layer[n], pos[n]) for n in nodes},
        bends={e: [(layer[d], pos[d]) for d in c] for e, c in chains.items()},
        rows=max((len(m) for m in layers.values()), default=0),
    )


@dataclass
class Box:
    """A box's absolute position on the page."""

    x: float
    y: float
    w: float
    h: float


@dataclass
class Link:
    """An arrow to route: from box `source` to box `target`.

    lanes: the x of the vertical run in each gap between columns it crosses,
        left to right. vias: the y of the horizontal run through each column
        in between (one fewer than lanes).
    """

    source: str
    target: str
    label: str
    style: str
    lanes: list[float]
    vias: list[float] = field(default_factory=list)


class Lanes:
    """Hands out x positions for vertical runs, spread across each gap."""

    def __init__(self, step: float = 12, spread: float = 60) -> None:
        self.step = step
        self.spread = spread
        self.used: dict[float, int] = defaultdict(int)

    def take(self, centre: float) -> float:
        """The next free lane around `centre`: 0, +step, -step, +2*step..."""
        i = self.used[centre]
        self.used[centre] += 1
        slots = int(self.spread // self.step) * 2 + 1
        k = i % slots
        offset = (k + 1) // 2 * self.step * (1 if k % 2 else -1)
        return centre + offset


def route(
    src: Box, dst: Box, exit_fy: float, entry_fy: float, link: Link
) -> tuple[list[tuple[float, float]], float]:
    """Corner points for an arrow, and where its label goes.

    The arrow leaves `src` on the right at `exit_fy` of its height, runs
    vertically only at link.lanes, horizontally at link.vias, and enters `dst`
    on the left at `entry_fy`. The label sits on the last horizontal stretch,
    next to the box it points at; draw.io measures label position from -1 at
    the source end to 1 at the target end.
    """
    start = (src.x + src.w, src.y + src.h * exit_fy)
    end = (dst.x, dst.y + dst.h * entry_fy)
    ys = [start[1]] + link.vias + [end[1]]
    points: list[tuple[float, float]] = []
    for i, lane in enumerate(link.lanes):
        points += [(lane, ys[i]), (lane, ys[i + 1])]
    path = [start] + points + [end]
    lengths = [
        abs(bx - ax) + abs(by - ay) for (ax, ay), (bx, by) in zip(path, path[1:])
    ]
    total = sum(lengths) or 1
    label_at = (total - lengths[-1] / 2) / total
    return points, 2 * label_at - 1


def connect(
    page: Page, ids: dict[str, str], boxes: dict[str, Box], links: list[Link]
) -> None:
    """Draw routed arrows, spreading several on one side of a box apart."""
    outgoing: dict[str, list[Link]] = defaultdict(list)
    incoming: dict[str, list[Link]] = defaultdict(list)
    for link in links:
        outgoing[link.source].append(link)
        incoming[link.target].append(link)

    def first_y(link: Link) -> float:
        return link.vias[0] if link.vias else boxes[link.target].y

    def last_y(link: Link) -> float:
        return link.vias[-1] if link.vias else boxes[link.source].y

    exit_at: dict[int, float] = {}
    entry_at: dict[int, float] = {}
    for members in outgoing.values():
        for i, link in enumerate(sorted(members, key=first_y)):
            exit_at[id(link)] = (i + 1) / (len(members) + 1)
    for members in incoming.values():
        for i, link in enumerate(sorted(members, key=last_y)):
            entry_at[id(link)] = (i + 1) / (len(members) + 1)

    for link in links:
        fx, fy = exit_at[id(link)], entry_at[id(link)]
        points, label_at = route(boxes[link.source], boxes[link.target], fx, fy, link)
        style = (
            link.style + f"exitX=1;exitY={fx:.3f};exitDx=0;exitDy=0;exitPerimeter=0;"
            f"entryX=0;entryY={fy:.3f};entryDx=0;entryDy=0;entryPerimeter=0;"
        )
        page.edge(
            ids[link.source], ids[link.target], link.label, style, points, label_at
        )


# --------------------------------------------------------------------------
# draw.io output


def node_style(
    colours: tuple[str, str],
    dashed: bool = False,
    width: int = 1,
    extra: str = "",
) -> str:
    """Style for a box: rounded, wrapped HTML label, given fill and stroke."""
    fill, stroke = colours
    style = (
        "rounded=1;whiteSpace=wrap;html=1;fontSize=11;arcSize=8;"
        f"fillColor={fill};strokeColor={stroke};strokeWidth={width};"
    )
    if dashed:
        style += "dashed=1;"
    return style + extra


def container_style(colours: tuple[str, str]) -> str:
    """Style for a labelled box that holds other boxes."""
    fill, stroke = colours
    return (
        "swimlane;html=1;whiteSpace=wrap;startSize=28;fontStyle=1;fontSize=12;"
        "container=1;collapsible=0;rounded=1;arcSize=4;"
        f"fillColor={fill};strokeColor={stroke};swimlaneFillColor=#ffffff;"
    )


def edge_style(stroke: str, dashed: bool = False, width: int = 1) -> str:
    """Style for a routed arrow: straight runs between the given corners."""
    style = (
        "edgeStyle=none;endArrow=block;endFill=1;html=1;rounded=1;"
        f"strokeColor={stroke};strokeWidth={width};fontSize=10;"
        "labelBackgroundColor=#ffffff;"
    )
    return style + ("dashed=1;" if dashed else "")


TEXT_STYLE = "text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=11;"
TITLE_STYLE = TEXT_STYLE + "fontSize=16;fontStyle=1;"
INTERNET_STYLE = (
    "ellipse;shape=cloud;whiteSpace=wrap;html=1;fontSize=12;fontStyle=1;"
    f"fillColor={RED[0]};strokeColor={RED[1]};"
)
LOOP_STYLE = (
    "edgeStyle=orthogonalEdgeStyle;endArrow=block;endFill=1;html=1;rounded=1;loop=1;"
    f"strokeColor={BLUE[1]};fontSize=10;labelBackgroundColor=#ffffff;"
)
BACK_STYLE = (
    "edgeStyle=orthogonalEdgeStyle;endArrow=block;endFill=1;html=1;rounded=1;"
    "strokeColor=#333333;fontSize=10;labelBackgroundColor=#ffffff;dashed=1;"
)


class Page:
    """One page of a draw.io file: boxes, containers and arrows."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.cells: list[ET.Element] = []
        self._next = 1  # cells 0 and 1 are the root and the default layer

    def _id(self) -> str:
        self._next += 1
        return f"c{self._next}"

    def vertex(
        self,
        label: str,
        x: float,
        y: float,
        w: float,
        h: float,
        style: str,
        parent: str = "1",
    ) -> str:
        """Add a box. `label` is HTML; x and y are relative to `parent`."""
        cell_id = self._id()
        cell = ET.Element(
            "mxCell", id=cell_id, value=label, style=style, vertex="1", parent=parent
        )
        ET.SubElement(
            cell,
            "mxGeometry",
            x=f"{x:g}",
            y=f"{y:g}",
            width=f"{w:g}",
            height=f"{h:g}",
            attrib={"as": "geometry"},
        )
        self.cells.append(cell)
        return cell_id

    def edge(
        self,
        source: str,
        target: str,
        label: str,
        style: str,
        points: list[tuple[float, float]] | None = None,
        label_at: float = 0.0,
    ) -> str:
        """Add an arrow from one cell to another, through absolute `points`."""
        cell_id = self._id()
        cell = ET.Element(
            "mxCell",
            id=cell_id,
            value=label,
            style=style,
            edge="1",
            parent="1",
            source=source,
            target=target,
        )
        geometry = ET.SubElement(
            cell, "mxGeometry", relative="1", attrib={"as": "geometry"}
        )
        if label_at:
            geometry.set("x", f"{label_at:.3f}")
        if points:
            array = ET.SubElement(geometry, "Array", attrib={"as": "points"})
            for x, y in points:
                ET.SubElement(array, "mxPoint", x=f"{x:g}", y=f"{y:g}")
        self.cells.append(cell)
        return cell_id

    def text(self, label: str, x: float, y: float, w: float, h: float) -> str:
        """Add free text."""
        return self.vertex(label, x, y, w, h, TEXT_STYLE)

    def title(self, label: str, subtitle: str = "") -> None:
        """Add the page heading at the top left."""
        self.vertex(esc(label), 20, 10, 1200, 28, TITLE_STYLE)
        if subtitle:
            self.text(subtitle, 20, 40, 1200, 36)

    def line(self, x1: float, y1: float, x2: float, y2: float, style: str) -> str:
        """Add a free-standing arrow between two points."""
        cell_id = self._id()
        cell = ET.Element(
            "mxCell", id=cell_id, value="", style=style, edge="1", parent="1"
        )
        geometry = ET.SubElement(
            cell, "mxGeometry", relative="1", attrib={"as": "geometry"}
        )
        for name, (x, y) in (("sourcePoint", (x1, y1)), ("targetPoint", (x2, y2))):
            ET.SubElement(
                geometry, "mxPoint", x=f"{x:g}", y=f"{y:g}", attrib={"as": name}
            )
        self.cells.append(cell)
        return cell_id

    def legend(self, items: list[tuple[str, str]], x: float, y: float) -> float:
        """Add a key: a sample box or arrow per (style, meaning). Returns its bottom."""
        self.vertex("<b>Key</b>", x, y, 200, 20, TEXT_STYLE)
        for i, (style, meaning) in enumerate(items):
            top = y + 26 + i * 30
            if "endArrow" in style:
                self.line(x, top + 10, x + 36, top + 10, style)
            else:
                self.vertex("", x, top, 36, 20, style)
            self.text(esc(meaning), x + 44, top, 330, 24)
        return y + 26 + len(items) * 30


def write_drawio(pages: list[Page], path: Path) -> None:
    """Write pages as an uncompressed .drawio file."""
    mxfile = ET.Element("mxfile", host="myawssgdiagrams")
    for i, page in enumerate(pages):
        diagram = ET.SubElement(mxfile, "diagram", id=f"p{i}", name=page.name)
        model = ET.SubElement(
            diagram,
            "mxGraphModel",
            grid="1",
            gridSize="10",
            guides="1",
            tooltips="1",
            connect="1",
            arrows="1",
            fold="1",
            page="0",
            pageScale="1",
            math="0",
            shadow="0",
        )
        root = ET.SubElement(model, "root")
        ET.SubElement(root, "mxCell", id="0")
        ET.SubElement(root, "mxCell", id="1", parent="0")
        root.extend(page.cells)
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(mxfile).write(path, encoding="utf-8", xml_declaration=True)


def group_label(group: Group, where: bool = False) -> str:
    """HTML label for a group box: name, ID, and what uses it."""
    lines = [f"<b>{esc(group.name or group.group_id)}</b>", group.group_id]
    if where:
        lines.append(esc(f"{group.profile} · {group.region} · {group.vpc_id}"))
    if group.attached_enis:
        used = f"used by {esc(group.attached_kinds or str(group.attached_enis))}"
        if group.public_enis:
            used += f" ({group.public_enis} public)"
        lines.append(used)
    else:
        lines.append("<i>unused</i>")
    return "<br>".join(lines)


def group_style(group: Group) -> str:
    """Box style for a group: risk colours when open to the internet, grey unused."""
    if group.exposure == "exposed":
        return node_style(RISK_COLOURS[group.internet_risk], width=3)
    if group.exposure == "open":
        return node_style(RISK_COLOURS[group.internet_risk], dashed=True, width=2)
    if not group.attached_enis:
        return node_style(GREY, dashed=True, extra="fontColor=#777777;")
    return node_style(BLUE)


GROUP_KEY = [
    (node_style(RED, width=3), "internet-reachable, risky ports: public IPs use it"),
    (node_style(AMBER, width=3), "internet-reachable, non-web ports"),
    (node_style(GREEN, width=3), "internet-reachable, web or ICMP only"),
    (
        node_style(RED, dashed=True, width=2),
        NOT_PUBLIC,
    ),
    (node_style(BLUE), IN_USE),
    (node_style(GREY, dashed=True), "unused: no network interface has it"),
]


def layered_page(
    page: Page,
    nodes: list[str],
    edges: dict[tuple[str, str], tuple[str, str]],
    labels: dict[str, str],
    styles: dict[str, str],
    size: tuple[float, float] = (230, 76),
    gap: float = 230,
    top: float = 100,
) -> tuple[dict[str, str], dict[str, Box], Layout]:
    """Lay out and draw a graph whose edges are {(source, target): (label, style)}.

    Returns the cell ids, the boxes, and the layout. Edges that point backwards
    (cycles) are left to draw.io's own routing.
    """
    width, height = size
    layout = layered_layout(nodes, list(edges))

    def col_x(lay: int) -> float:
        return 40 + lay * (width + gap)

    def row_y(row: int) -> float:
        return top + row * (height + 40)

    ids: dict[str, str] = {}
    boxes: dict[str, Box] = {}
    for n, (lay, row) in layout.positions.items():
        boxes[n] = Box(col_x(lay), row_y(row), width, height)
        ids[n] = page.vertex(labels[n], *vars(boxes[n]).values(), styles[n])

    lanes = Lanes(spread=min(60, gap / 2 - 30))
    links = []
    for (a, b), (label, style) in edges.items():
        la, lb = layout.positions[a][0], layout.positions[b][0]
        if la >= lb:
            page.edge(ids[a], ids[b], label, BACK_STYLE)
            continue
        centres = [col_x(lay) + width + gap / 2 for lay in range(la, lb)]
        vias = [row_y(row) + height / 2 for _, row in layout.bends.get((a, b), [])]
        links.append(Link(a, b, label, style, [lanes.take(c) for c in centres], vias))
    connect(page, ids, boxes, links)
    return ids, boxes, layout


# --------------------------------------------------------------------------
# Map 1: group connections, one page per VPC


@dataclass
class VpcGraph:
    """Map 1's graph for one VPC.

    nodes: group IDs, plus "internet" and groups outside the VPC as needed.
    flows: {(from, to): [port labels]}; a group's rule naming itself is a
        flow from the group to itself.
    egress: the flows that come from egress rules.
    risks: for flows from the internet, the worst rule risk.
    """

    nodes: list[str] = field(default_factory=list)
    labels: dict[str, str] = field(default_factory=dict)
    styles: dict[str, str] = field(default_factory=dict)
    flows: dict[tuple[str, str], list[str]] = field(
        default_factory=lambda: defaultdict(list)
    )
    egress: set[tuple[str, str]] = field(default_factory=set)
    risks: dict[tuple[str, str], str] = field(default_factory=dict)

    def add_node(self, node: str, label: str, style: str) -> None:
        """Add a node once."""
        if node not in self.labels:
            self.nodes.append(node)
            self.labels[node] = label
            self.styles[node] = style


def outside_label(group_id: str, account: str, known: Group | None, vpc_id: str) -> str:
    """Label for a group a rule names that isn't in the VPC being drawn."""
    lines = [f"<b>{esc(known.name)}</b>" if known and known.name else "", group_id]
    if account:
        lines.append(f"account {account}")
    elif known and known.vpc_id != vpc_id:
        lines.append(f"in {known.vpc_id}")
    else:
        lines.append("outside this VPC")
    return "<br>".join(x for x in lines if x)


def vpc_graph(members: list[Group], by_id: dict[str, Group], vpc_id: str) -> VpcGraph:
    """Map 1's nodes and flows for the groups in one VPC."""
    graph = VpcGraph()
    for g in members:
        graph.add_node(g.group_id, group_label(g), group_style(g))
    for g in members:
        for r in g.rules:
            if r.is_internet:
                pair = ("internet", g.group_id)
                graph.flows[pair].append(port_label(r))
                old = graph.risks.get(pair, "low")
                graph.risks[pair] = max(old, rule_risk(r), key=RISK_ORDER.get)
            elif r.source_type == "security-group":
                other, account = parse_sg_ref(r.source)
                label = outside_label(other, account, by_id.get(other), vpc_id)
                graph.add_node(other, label, node_style(YELLOW, dashed=True))
                if r.direction == "ingress":
                    pair = (other, g.group_id)
                else:
                    pair = (g.group_id, other)
                    graph.egress.add(pair)
                graph.flows[pair].append(port_label(r))
    if graph.risks:
        graph.nodes.insert(0, "internet")
        graph.labels["internet"] = "Internet<br>0.0.0.0/0 · ::/0"
        graph.styles["internet"] = INTERNET_STYLE
    return graph


def vpc_edges(graph: VpcGraph) -> dict[tuple[str, str], tuple[str, str]]:
    """Map 1's arrows, {(from, to): (label, style)}, without self-references."""
    edges = {}
    for pair, ports in graph.flows.items():
        if pair[0] == pair[1]:
            continue
        label = join_labels(ports)
        if pair[0] == "internet":
            style = edge_style(RISK_COLOURS[graph.risks[pair]][1], width=2)
        elif pair in graph.egress:
            label, style = "egress " + label, edge_style(DARK, dashed=True)
        else:
            style = edge_style(DARK)
        edges[pair] = (esc(label), style)
    return edges


CONNECTIONS_KEY = GROUP_KEY + [
    (node_style(YELLOW, dashed=True), "group outside this VPC or account"),
    (edge_style(DARK), "ingress rule: traffic allowed this way"),
    (edge_style(DARK, dashed=True), "egress rule naming another group"),
    (LOOP_STYLE, "rule allowing the group's own members"),
]


def draw_vpc(page: Page, graph: VpcGraph) -> None:
    """Draw map 1 for one VPC: linked groups in layers, the rest in a grid."""
    edges = vpc_edges(graph)
    linked = {n for pair in edges for n in pair}
    size = (230, 76)
    ids, _, layout = layered_page(
        page,
        [n for n in graph.nodes if n in linked],
        edges,
        graph.labels,
        graph.styles,
        size,
    )
    columns = max((p[0] + 1 for p in layout.positions.values()), default=0)

    alone = [n for n in graph.nodes if n not in linked]
    top = 100 + layout.rows * (size[1] + 40) + (40 if layout.rows else 0)
    if alone:
        page.text("<b>Groups with no group-to-group rules</b>", 40, top, 400, 20)
    for i, n in enumerate(alone):
        x = 40 + (i % 5) * (size[0] + 30)
        y = top + 30 + (i // 5) * (size[1] + 40)
        ids[n] = page.vertex(graph.labels[n], x, y, *size, graph.styles[n])
    for (src, dst), ports in graph.flows.items():
        if src == dst:
            label = esc("self: " + join_labels(ports))
            page.edge(ids[src], ids[dst], label, LOOP_STYLE)

    legend_x = max(40 + columns * (size[0] + 230), 40 + 5 * (size[0] + 30)) + 20
    bottom = page.legend(CONNECTIONS_KEY, legend_x, 100)
    page.text(
        "Address-range rules other than the internet are in 4-network-origins.",
        legend_x,
        bottom + 10,
        360,
        36,
    )


def build_connections(groups: list[Group], vpcs: list[Vpc]) -> dict[str, list[Page]]:
    """Map 1: per profile, one page per VPC of its groups and their links."""
    by_id = {g.group_id: g for g in groups}
    vpc_info = {(v.account_id, v.region, v.vpc_id): v for v in vpcs}
    by_vpc: dict[tuple[str, str, str], list[Group]] = defaultdict(list)
    for g in groups:
        by_vpc[(g.account_id, g.region, g.vpc_id)].append(g)

    pages: dict[str, list[Page]] = defaultdict(list)
    for key, members in sorted(
        by_vpc.items(), key=lambda kv: (kv[1][0].profile, kv[0][1], kv[0][2])
    ):
        account, region, vpc_id = key
        profile = members[0].profile
        vpc = vpc_info.get(key)
        name = (vpc.name if vpc else "") or vpc_id
        page = Page(f"{region} {name}"[:60])
        sub = f"{profile} ({account}) · {region} · {vpc_id}"
        if vpc:
            sub += f" · {' '.join(vpc.cidrs)}" + (
                " · default VPC" if vpc.is_default else ""
            )
        page.title(f"Security group connections: {name}", esc(sub))
        draw_vpc(page, vpc_graph(members, by_id, vpc_id))
        pages[profile].append(page)
    return pages


# --------------------------------------------------------------------------
# Map 2: internet exposure


def build_exposure(groups: list[Group]) -> Page:
    """Map 2: every group open to the internet, by account and VPC."""
    page = Page("Internet exposure")
    open_groups = [g for g in groups if g.internet_rules]
    exposed = sum(1 for g in open_groups if g.exposure == "exposed")
    page.title(
        "Security groups that allow inbound traffic from the internet",
        esc(
            f"{plural(len(open_groups), 'group')} allow 0.0.0.0/0 or ::/0; "
            f"{exposed} used by something with a public IP. "
            "Arrows are labelled with the ports they open."
        ),
    )
    if not open_groups:
        page.text(
            "No security group allows inbound traffic from the internet.",
            40,
            100,
            600,
            24,
        )
        return page

    # One column of groups, so every arrow comes straight in from the left
    width, height, gap, pad = 260, 76, 20, 28
    by_account: dict[str, dict[tuple[str, str], list[Group]]] = defaultdict(
        lambda: defaultdict(list)
    )
    ranked = sorted(
        open_groups,
        key=lambda g: (
            -RISK_ORDER[g.internet_risk],
            g.exposure != "exposed",
            g.group_id,
        ),
    )
    for g in ranked:
        by_account[f"{g.profile} ({g.account_id})"][(g.region, g.vpc_id)].append(g)

    x0, y = 560, 100
    ids: dict[str, str] = {}
    boxes: dict[str, Box] = {}
    for account in sorted(by_account):
        vpcs = by_account[account]
        vh = {k: pad + len(m) * (height + gap) + gap for k, m in vpcs.items()}
        acct_h = pad + sum(h + gap for h in vh.values()) + gap
        acct_w = width + 4 * gap
        acct = page.vertex(esc(account), x0, y, acct_w, acct_h, container_style(PURPLE))
        vy = pad + gap
        for (region, vpc_id), members in vpcs.items():
            box = page.vertex(
                esc(f"{region} · {vpc_id}"),
                gap,
                vy,
                width + 2 * gap,
                vh[(region, vpc_id)],
                container_style(BLUE),
                acct,
            )
            for i, g in enumerate(members):
                gy = pad + gap + i * (height + gap)
                key = f"{g.account_id}/{g.region}/{g.group_id}"
                ids[key] = page.vertex(
                    group_label(g), gap, gy, width, height, group_style(g), box
                )
                boxes[key] = Box(x0 + 2 * gap, y + vy + gy, width, height)
            vy += vh[(region, vpc_id)] + gap
        y += acct_h + 40

    cloud = Box(40, max(100, (100 + y) / 2 - 70), 220, 140)
    ids["internet"] = page.vertex(
        "Internet<br>0.0.0.0/0 · ::/0", *vars(cloud).values(), INTERNET_STYLE
    )
    boxes["internet"] = cloud
    lanes = Lanes(spread=60)
    centre = cloud.x + cloud.w + 70
    links = []
    for g in ranked:
        key = f"{g.account_id}/{g.region}/{g.group_id}"
        label = esc(join_labels([port_label(r) for r in g.internet_rules], limit=5))
        colour = RISK_COLOURS[g.internet_risk][1]
        style = edge_style(colour, dashed=g.exposure != "exposed", width=2)
        links.append(Link("internet", key, label, style, [lanes.take(centre)]))
    connect(page, ids, boxes, links)
    page.legend(GROUP_KEY[:4], 40, y + 20)
    return page


# --------------------------------------------------------------------------
# Map 3: cross-account trust


def cross_account_links(
    groups: list[Group], vpcs: list[Vpc]
) -> tuple[dict[tuple[str, str], list[str]], dict[tuple[str, str], list[str]]]:
    """Links between accounts, each keyed (from account, to account).

    Returns (trust, shared). trust: rules allowing traffic from a group in one
    account to a group in another, as "tcp 443 web → app". shared: VPCs one
    account owns and shares with another, as "vpc-1 (us-east-1)".
    """
    names = {g.group_id: g.name or g.group_id for g in groups}
    trust: dict[tuple[str, str], list[str]] = defaultdict(list)
    shared: dict[tuple[str, str], list[str]] = defaultdict(list)
    for g in groups:
        here = g.name or g.group_id
        for r in g.rules:
            other, account = parse_sg_ref(r.source)
            if r.source_type != "security-group" or account in ("", g.account_id):
                continue
            there = names.get(other, other)
            if r.direction == "ingress":
                pair, flow = (account, g.account_id), f"{there} → {here}"
            else:
                pair, flow = (g.account_id, account), f"{here} → {there}"
            trust[pair].append(f"{port_label(r)} {flow}")
    for v in vpcs:
        if v.owner_id and v.owner_id != v.account_id:
            shared[(v.owner_id, v.account_id)].append(f"{v.vpc_id} ({v.region})")
    return trust, shared


def account_link_label(rules: list[str], shares: list[str]) -> str:
    """HTML label for a cross-account arrow: one rule per line, at most three.

    One per line keeps the label narrower than the gap it sits in.
    """
    lines = []
    if rules:
        distinct = list(dict.fromkeys(rules))
        lines.append(f"{plural(len(rules), 'rule')}:")
        lines += distinct[:3]
        if len(distinct) > 3:
            lines.append(f"+{len(distinct) - 3} more")
    if shares:
        lines.append("shares " + join_labels(shares, 2))
    return "<br>".join(esc(line) for line in lines)


def build_cross_account(groups: list[Group], vpcs: list[Vpc]) -> Page:
    """Map 3: accounts linked by group references and shared VPCs."""
    page = Page("Cross-account")
    page.title(
        "Cross-account links",
        "An arrow means security group rules allow traffic from the first account "
        "into the second, or the first account shares one of its VPCs with the second.",
    )
    trust, shared = cross_account_links(groups, vpcs)
    pairs = list(dict.fromkeys(list(trust) + list(shared)))
    if not pairs:
        page.text(
            "No security group references another account, and no VPC is shared.",
            40,
            100,
            700,
            24,
        )
        return page

    profiles = {g.account_id: g.profile for g in groups}
    profiles.update({v.account_id: v.profile for v in vpcs})
    accounts = list(dict.fromkeys(a for pair in pairs for a in pair))
    labels, styles = {}, {}
    for acct in accounts:
        scanned = acct in profiles
        name = esc(profiles[acct]) if scanned else "not scanned"
        labels[acct] = f"<b>{name}</b><br>{acct}"
        styles[acct] = node_style(BLUE) if scanned else node_style(YELLOW, dashed=True)
    edges = {}
    for pair in pairs:
        if pair in trust:
            style = edge_style(DARK, width=2)
        else:
            style = edge_style(PURPLE[1], dashed=True, width=2)
        label = account_link_label(trust.get(pair, []), shared.get(pair, []))
        edges[pair] = (label, style)
    gap = 420
    _, _, layout = layered_page(page, accounts, edges, labels, styles, (220, 60), gap)
    depth = max(p[0] for p in layout.positions.values()) + 1
    page.legend(
        [
            (node_style(BLUE), "scanned account"),
            (node_style(YELLOW, dashed=True), "account not in the scan"),
            (edge_style(DARK, width=2), "security group rules allow traffic →"),
            (edge_style(PURPLE[1], dashed=True, width=2), "VPC owner shares a VPC →"),
        ],
        40 + depth * (220 + gap),
        100,
    )
    return page


# --------------------------------------------------------------------------
# Map 4: network origins


ORIGIN_COLOURS = {
    "prefix-list": PURPLE,
    "aws": BLUE,
    "private": YELLOW,
    "public": AMBER,
}


def build_origins(groups: list[Group], vpcs: list[Vpc]) -> Page:
    """Map 4: address ranges and prefix lists that rules allow traffic from."""
    page = Page("Network origins")
    own = {(v.account_id, v.region, v.vpc_id): v.cidrs for v in vpcs}
    sources: dict[str, tuple[str, str]] = {}
    flows: dict[tuple[str, str], list[str]] = defaultdict(list)
    members: dict[str, Group] = {}
    for g in groups:
        for r in g.rules:
            if r.direction != "ingress":
                continue
            found = classify_source(
                r, own.get((g.account_id, g.region, g.vpc_id), []), vpcs
            )
            if found is None:
                continue
            sources.setdefault(r.source, found)
            key = f"{g.account_id}/{g.region}/{g.group_id}"
            members[key] = g
            flows[(r.source, key)].append(port_label(r))

    page.title(
        "Where traffic is allowed from",
        "Address ranges and prefix lists in inbound rules, other than the internet "
        "and the group's own VPC. Look here for old office, VPN and vendor addresses.",
    )
    if not flows:
        page.text(
            "No rule allows an address range outside its own VPC, "
            "other than the internet.",
            40,
            100,
            700,
            24,
        )
        return page

    order = {"public": 0, "private": 1, "aws": 2, "prefix-list": 3}
    src_nodes = sorted(sources, key=lambda s: (order[sources[s][0]], s))
    labels = {s: sources[s][1] for s in src_nodes}
    styles = {s: node_style(ORIGIN_COLOURS[sources[s][0]]) for s in src_nodes}
    for key, g in members.items():
        labels[key] = group_label(g, where=True)
        styles[key] = group_style(g)
    edges = {
        pair: (esc(join_labels(ports)), edge_style(DARK))
        for pair, ports in flows.items()
    }
    layered_page(page, src_nodes + list(members), edges, labels, styles, (260, 70), 260)
    page.legend(
        [
            (node_style(AMBER), "public range: office, partner or vendor addresses"),
            (node_style(YELLOW), "private range outside every scanned VPC"),
            (node_style(BLUE), "inside another scanned VPC"),
            (node_style(PURPLE), "managed prefix list"),
        ],
        40 + 2 * (260 + 260),
        100,
    )
    return page


# --------------------------------------------------------------------------
# Map 5: org footprint


def vpc_risk(groups: list[Group]) -> tuple[tuple[str, str], str]:
    """Colour and one-line verdict for a VPC from its groups."""
    exposed = [g for g in groups if g.exposure == "exposed"]
    if any(g.internet_risk == "high" for g in exposed):
        return RED, "risky ports reachable from the internet"
    if any(g.internet_risk == "medium" for g in exposed):
        return AMBER, "non-web ports reachable from the internet"
    if exposed:
        return GREEN, "internet-facing: web or ICMP only"
    if any(g.exposure == "open" for g in groups):
        return YELLOW, NOT_PUBLIC
    if any(g.attached_enis for g in groups):
        return BLUE, IN_USE
    return GREY, "nothing attached"


FOOTPRINT_KEY = [
    (node_style(RED), "risky ports reachable from the internet"),
    (node_style(AMBER), "non-web ports reachable from the internet"),
    (node_style(GREEN), "internet-facing: web or ICMP only"),
    (node_style(YELLOW), NOT_PUBLIC),
    (node_style(BLUE), IN_USE),
    (node_style(GREY), "nothing attached"),
]
VPC_W, VPC_H, GAP, VPC_COLS = 250, 104, 16, 4


def vpc_summary(vpc: Vpc, members: list[Group]) -> tuple[str, tuple[str, str]]:
    """Map 5's HTML label and colours for one VPC and its groups."""
    colours, verdict = vpc_risk(members)
    unused = sum(1 for g in members if not g.attached_enis)
    exposed = sum(1 for g in members if g.exposure == "exposed")
    lines = [
        f"<b>{esc(vpc.name or vpc.vpc_id)}</b>"
        + (" (default)" if vpc.is_default else ""),
        f"{vpc.vpc_id} · {esc(' '.join(vpc.cidrs))}",
        esc(vpc.contents) if vpc.contents else "<i>no network interfaces</i>",
        f"{plural(len(members), 'group')}, {unused} unused, "
        f"{exposed} internet-reachable",
        f"<i>{esc(verdict)}</i>",
    ]
    if vpc.owner_id and vpc.owner_id != vpc.account_id:
        lines.insert(1, f"shared from {vpc.owner_id}")
    return "<br>".join(lines), colours


def region_size(count: int) -> tuple[float, float]:
    """Size of a region box holding `count` VPCs, up to VPC_COLS a row."""
    cols = min(VPC_COLS, count)
    rows = -(-count // cols)
    return cols * (VPC_W + GAP) + GAP, 28 + rows * (VPC_H + GAP) + GAP


def account_size(regions: dict[str, list[Vpc]]) -> tuple[float, float]:
    """Size of an account box holding its region boxes, stacked."""
    sizes = [region_size(len(v)) for v in regions.values()]
    width = max(w for w, _ in sizes) + 2 * GAP
    return width, 28 + sum(h + GAP for _, h in sizes) + GAP


def draw_account(
    page: Page,
    title: str,
    regions: dict[str, list[Vpc]],
    by_vpc: dict[tuple[str, str, str], list[Group]],
    x: float,
    y: float,
) -> None:
    """Draw one account box at (x, y): its regions, each with its VPCs."""
    acct = page.vertex(
        esc(title), x, y, *account_size(regions), container_style(PURPLE)
    )
    ry = 28 + GAP
    for region in sorted(regions):
        rw, rh = region_size(len(regions[region]))
        box = page.vertex(esc(region), GAP, ry, rw, rh, container_style(GREY), acct)
        ordered = sorted(regions[region], key=lambda v: (v.is_default, v.vpc_id))
        for i, v in enumerate(ordered):
            members = by_vpc.get((v.account_id, v.region, v.vpc_id), [])
            label, colours = vpc_summary(v, members)
            vx = GAP + (i % VPC_COLS) * (VPC_W + GAP)
            vy = 28 + GAP + (i // VPC_COLS) * (VPC_H + GAP)
            page.vertex(label, vx, vy, VPC_W, VPC_H, node_style(colours), box)
        ry += rh + GAP


def build_footprint(groups: list[Group], vpcs: list[Vpc]) -> Page:
    """Map 5: account > region > VPC, coloured by internet exposure."""
    page = Page("Org footprint")
    by_vpc: dict[tuple[str, str, str], list[Group]] = defaultdict(list)
    for g in groups:
        by_vpc[(g.account_id, g.region, g.vpc_id)].append(g)
    tree: dict[tuple[str, str], dict[str, list[Vpc]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for v in vpcs:
        tree[(v.profile, v.account_id)][v.region].append(v)
    regions = {r for acct in tree.values() for r in acct}
    page.title(
        "Org footprint",
        esc(
            f"{plural(len(tree), 'account')}, {plural(len(regions), 'region')}, "
            f"{plural(len(vpcs), 'VPC')} in use. Each VPC is coloured by the worst "
            "internet exposure of its security groups."
        ),
    )

    # Accounts left to right, wrapping to a new row past right_edge
    x, y, row_h, right_edge = 40, 100, 0, 3000
    for profile, account in sorted(tree):
        width, height = account_size(tree[(profile, account)])
        if x > 40 and x + width > right_edge:
            x, y, row_h = 40, y + row_h + 40, 0
        draw_account(
            page, f"{profile} ({account})", tree[(profile, account)], by_vpc, x, y
        )
        x += width + 40
        row_h = max(row_h, height)
    page.legend(FOOTPRINT_KEY, 40, y + row_h + 50)
    return page


# --------------------------------------------------------------------------


def safe_name(text: str) -> str:
    """A file name made of letters, digits, dots, dashes and underscores."""
    return re.sub(r"[^A-Za-z0-9._-]", "_", text) or "_"


def main(argv: list[str] | None = None) -> int:
    """Build all five diagrams; return the exit status."""
    parser = argparse.ArgumentParser(
        description="Draw.io diagrams of AWS security groups.",
        epilog="regions.csv comes from myawsgetregions.sh, "
        "secgroups.csv from myawsgetsecgroups.sh.",
    )
    parser.add_argument("regions", type=Path, help="regions.csv")
    parser.add_argument("secgroups", type=Path, help="secgroups.csv")
    parser.add_argument("outdir", type=Path, help="directory for the .drawio files")
    args = parser.parse_args(argv)

    try:
        vpcs = load_vpcs(args.regions)
        groups = load_groups(args.secgroups)
    except (OSError, KeyError, csv.Error) as e:
        print(f"FAIL: can't read the CSVs: {e}", file=sys.stderr)
        return 1
    if not groups:
        print(
            f"FAIL: no security groups with status ok in {args.secgroups}",
            file=sys.stderr,
        )
        return 1

    out = args.outdir
    for profile, pages in build_connections(groups, vpcs).items():
        write_drawio(pages, out / "1-sg-connections" / f"{safe_name(profile)}.drawio")
    write_drawio([build_exposure(groups)], out / "2-internet-exposure.drawio")
    write_drawio([build_cross_account(groups, vpcs)], out / "3-cross-account.drawio")
    write_drawio([build_origins(groups, vpcs)], out / "4-network-origins.drawio")
    write_drawio([build_footprint(groups, vpcs)], out / "5-org-footprint.drawio")
    print(
        f"Wrote diagrams for {plural(len(groups), 'security group')} to {out}/",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
