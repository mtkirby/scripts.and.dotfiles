#!/usr/bin/env bash
# List every security group, and each of its rules, in the VPCs that
# myawsgetregions.sh found, as CSV.
#
# Usage: myawsgetregions.sh profiles.txt > regions.csv
#        myawsgetsecgroups.sh regions.csv > secgroups.csv
#   Rows of regions.csv whose status isn't "ok" or that have no vpc_id are skipped.
#   JOBS=N sets how many accounts are scanned at once (default 8).
#
# One row per rule; a group with no rules gets one row with the rule columns empty.
# Columns:
#   profile,account_id,region,vpc_id,group_id,group_name,group_description,
#   group_owner_id,group_tags,attached_enis,public_enis,attached_kinds,rule_id,
#   direction,protocol,from_port,to_port,source_type,source,rule_description,
#   rule_tags,status
#   attached_enis: network interfaces using the group; 0 means nothing uses it.
#   public_enis: of those, how many have a public IP (reachable from the internet
#     if the rules allow it).
#   attached_kinds: what uses the group, e.g. "ec2:2 ELB:1 lambda:1".
#   protocol/from_port/to_port: "all" where AWS uses -1. For ICMP the ports are
#     the ICMP type and code.
#   source_type: ipv4, ipv6, prefix-list or security-group. For egress rules it's
#     the destination. A group in another account is shown as "sg-... (account N)".
#   Tags are "Key=Value; Key=Value".
#   status is "ok", or the error, e.g. a region an SCP denies.
#   Progress and warnings go to stderr, so only the CSV lands in the file.

set -o pipefail
export AWS_PAGER="" AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10

# One CSV row from the arguments, quoted as needed
csv()
{
    jq -rn '$ARGS.positional | @csv' --args "$@"
}

# A row for an error: profile, account, region, vpcs, then the message as status
errrow()
{
    csv "$1" "$2" "$3" "$4" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "${5//$'\n'/ }"
}

# Write the rows for one account to <dir>/<index>.csv. <dir>/<index>.targets
# holds its "region vpc_id" lines.
one_account()
{
    local dir="$1" index="$2" profile="$3" account="$4"
    local out="$dir/$index.csv" targets="$dir/$index.targets" region vpcs err
    local sgs="$dir/$index.sgs.json" rules="$dir/$index.rules.json" enis="$dir/$index.enis.json"

    : >"$out"
    # Not "while read": aws inside the loop could eat its input. Regions have no spaces.
    # shellcheck disable=SC2013
    for region in $(awk '!seen[$1]++ { print $1 }' "$targets")
    do
        vpcs="$(awk -v r="$region" '$1 == r { print $2 }' "$targets" | paste -sd, -)"
        # Files, not variables: a busy region's output can outgrow a command line
        if ! err="$(aws ec2 describe-security-groups --profile "$profile" --region "$region" \
            --filters "Name=vpc-id,Values=$vpcs" --output json 2>&1 >"$sgs")"
        then
            errrow "$profile" "$account" "$region" "$vpcs" "error: $err" >>"$out"
            continue
        fi
        if ! err="$(aws ec2 describe-security-group-rules --profile "$profile" --region "$region" \
            --output json 2>&1 >"$rules")"
        then
            errrow "$profile" "$account" "$region" "$vpcs" "error: $err" >>"$out"
            continue
        fi
        if ! err="$(aws ec2 describe-network-interfaces --profile "$profile" --region "$region" \
            --filters "Name=vpc-id,Values=$vpcs" --output json 2>&1 >"$enis")"
        then
            errrow "$profile" "$account" "$region" "$vpcs" "error: $err" >>"$out"
            continue
        fi
        jq -rn --arg p "$profile" --arg a "$account" --arg r "$region" \
            --slurpfile g "$sgs" --slurpfile sr "$rules" --slurpfile e "$enis" '
            def tags: [.[]? | "\(.Key)=\(.Value)"] | join("; ");
            def all: if . == -1 or . == "-1" then "all" else (. // "" | tostring) end;
            # Same kinds as myawsgetregions.sh: the interface type, "ec2" for an
            # instance, else the first word of the description of managed ones
            def kind: if .InterfaceType != "interface" then .InterfaceType
                elif .Attachment.InstanceId then "ec2"
                else ((.Description // "") | split(" ")[0] | if . == "" then "other" else . end)
                end;

            (reduce $sr[0].SecurityGroupRules[] as $x ({}; .[$x.GroupId] += [$x])) as $rules
            | (reduce $e[0].NetworkInterfaces[] as $n ({};
                reduce ($n.Groups[]?.GroupId) as $id (.; .[$id] += [$n]))) as $used
            | $g[0].SecurityGroups[]
            | ($used[.GroupId] // []) as $in
            | [$p, $a, $r, .VpcId, .GroupId, .GroupName, (.Description // ""), .OwnerId,
               (.Tags | tags), ($in | length),
               ([$in[] | select(.Association.PublicIp)] | length),
               ($in | map(kind) | group_by(.) | map("\(.[0]):\(length)") | join(" "))] as $group
            | ($rules[.GroupId] // [] | sort_by(.IsEgress, .IpProtocol, .FromPort)) as $rs
            | if ($rs | length) == 0 then
                $group + ["", "", "", "", "", "", "", "", "", "ok"]
            else
                $rs[] | $group + [
                    .SecurityGroupRuleId,
                    (if .IsEgress then "egress" else "ingress" end),
                    (.IpProtocol | all), (.FromPort | all), (.ToPort | all),
                    (if .CidrIpv4 then "ipv4", .CidrIpv4
                     elif .CidrIpv6 then "ipv6", .CidrIpv6
                     elif .PrefixListId then "prefix-list", .PrefixListId
                     elif .ReferencedGroupInfo then "security-group",
                        (.ReferencedGroupInfo
                         | .GroupId + (if .UserId and .UserId != $a then " (account \(.UserId))" else "" end))
                     else "", "" end),
                    (.Description // ""), (.Tags | tags), "ok"]
            end
            | @csv' >>"$out"
    done
    rm -f "$sgs" "$rules" "$enis"
    echo "done: $profile ($account)" >&2
}

if [[ "$1" == --one ]]
then
    one_account "$2" "$3" "$4" "$5"
    exit 0
fi

if [[ ! -r "$1" ]]
then
    echo "Usage: ${0##*/} regions.csv > secgroups.csv  (regions.csv from myawsgetregions.sh)" >&2
    exit 1
fi
for cmd in aws jq python3
do
    if ! command -v "$cmd" >/dev/null 2>&1
    then
        echo "FAIL: $cmd not found" >&2
        exit 1
    fi
done

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Python reads the CSV, since VPC names can hold quoted commas. One line per VPC:
# account index (first-seen order), profile, account, region, vpc_id
if ! python3 -I -c '
import csv, sys
seen = {}
rows = csv.DictReader(open(sys.argv[1], newline=""))
need = {"profile", "account_id", "region", "vpc_id", "status"}
if not need <= set(rows.fieldnames or []):
    sys.exit("FAIL: %s is not myawsgetregions.sh output" % sys.argv[1])
for row in rows:
    if row["status"] != "ok" or not row["vpc_id"]:
        continue
    i = seen.setdefault(row["profile"], len(seen))
    print(i, row["profile"], row["account_id"], row["region"], row["vpc_id"])
' "$1" >"$tmp/vpcs"
then
    exit 1
fi
if [[ ! -s "$tmp/vpcs" ]]
then
    echo "FAIL: no VPCs with status ok in $1" >&2
    exit 1
fi

# Per account: its "region vpc_id" lines, and one "index profile account" job
while read -r i profile account region vpc
do
    echo "$region $vpc" >>"$tmp/$i.targets"
done <"$tmp/vpcs"
awk '!seen[$1]++ { print $1, $2, $3 }' "$tmp/vpcs" >"$tmp/jobs"

# All the SSO profiles share one login, so check it once before starting
read -r _ first _ <"$tmp/jobs"
if ! aws sts get-caller-identity --profile "$first" >/dev/null 2>&1
then
    if command -v aws-sso-util >/dev/null 2>&1
    then
        echo "SSO login needed; running aws-sso-util login" >&2
        aws-sso-util login >&2 || exit 1
    else
        echo "WARN: $first can't log in; run aws-sso-util login first" >&2
    fi
fi

echo "Scanning $(wc -l <"$tmp/jobs" | tr -d ' ') accounts, $(wc -l <"$tmp/vpcs" | tr -d ' ') VPCs, ${JOBS:-8} accounts at a time" >&2
xargs -n 3 -P "${JOBS:-8}" bash "$0" --one "$tmp" <"$tmp/jobs"

csv profile account_id region vpc_id group_id group_name group_description \
    group_owner_id group_tags attached_enis public_enis attached_kinds rule_id \
    direction protocol from_port to_port source_type source rule_description \
    rule_tags status
while read -r i _ _
do
    cat "$tmp/$i.csv" 2>/dev/null
done <"$tmp/jobs"
