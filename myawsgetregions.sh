#!/usr/bin/env bash
# Show which regions each AWS account actually uses, as CSV: one row per VPC
# that has something in it or that someone created.
#
# Usage: myawsgetregions.sh profiles.txt > regions.csv
#   profiles.txt: one AWS CLI profile per line; blank lines and # comments are
#   ignored. Profile names can't contain spaces. Typically these are the SSO
#   profiles "aws-sso-util configure populate" wrote to ~/.aws/config.
#   JOBS=N sets how many accounts are scanned at once (default 8).
#
# A VPC is listed if it isn't a default VPC (someone made it), or if it's a
# default VPC with network interfaces in it. AWS creates an empty default VPC in
# every region of every account, so those alone don't mean a region is used.
# Almost everything that runs in a VPC (EC2, RDS, load balancers, VPC Lambda,
# NAT gateways, endpoints, EFS) gets a network interface. Regions with neither
# get no rows. Services that run outside a VPC (S3, DynamoDB, SQS, non-VPC
# Lambda) aren't detected.
#
# Columns: profile,account_id,region,vpc_id,vpc_name,cidr_blocks,is_default,owner_id,eni_count,contents,status
#   contents: network interfaces by kind, e.g. "ec2:3 lambda:2 RDSNetworkInterface:1"
#   owner_id differs from account_id for a VPC shared in from another account (RAM).
#   status is "ok", or the error, e.g. a login failure or a region an SCP denies.
#   Progress and warnings go to stderr, so only the CSV lands in the file.

set -o pipefail
export AWS_PAGER="" AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10

# One CSV row from the arguments, quoted as needed
csv()
{
    jq -rn '$ARGS.positional | @csv' --args "$@"
}

# A row for an error: profile, account, region, then the message as status
errrow()
{
    csv "$1" "$2" "$3" "" "" "" "" "" "" "" "${4//$'\n'/ }"
}

# Write the rows for one account to <dir>/<index>.csv
one_account()
{
    local profile="$3" out="$1/$2.csv" vpcs="$1/$2.vpcs.json" enis="$1/$2.enis.json"
    local account regions region home err

    if ! account="$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>&1)"
    then
        errrow "$profile" "" "" "login failed: $account" >"$out"
        echo "FAIL: $profile: login failed" >&2
        return
    fi

    # Enabled regions only; opt-in regions the account hasn't enabled are left out
    home="$(aws configure get region --profile "$profile")"
    if ! regions="$(aws ec2 describe-regions --profile "$profile" --region "${home:-us-east-1}" \
        --query 'Regions[].RegionName' --output text 2>&1)"
    then
        errrow "$profile" "$account" "" "describe-regions failed: $regions" >"$out"
        echo "FAIL: $profile: can't list regions" >&2
        return
    fi

    : >"$out"
    for region in $regions
    do
        # Files, not variables: a busy region's interfaces can outgrow a command line
        if ! err="$(aws ec2 describe-vpcs --profile "$profile" --region "$region" \
            --output json 2>&1 >"$vpcs")"
        then
            errrow "$profile" "$account" "$region" "error: $err" >>"$out"
            continue
        fi
        if ! err="$(aws ec2 describe-network-interfaces --profile "$profile" --region "$region" \
            --output json 2>&1 >"$enis")"
        then
            errrow "$profile" "$account" "$region" "error: $err" >>"$out"
            continue
        fi
        jq -rn --arg p "$profile" --arg a "$account" --arg r "$region" \
            --slurpfile v "$vpcs" --slurpfile e "$enis" '
            $e[0].NetworkInterfaces as $enis
            | $v[0].Vpcs[]
            | . as $vpc
            | [$enis[] | select(.VpcId == $vpc.VpcId)] as $in
            | select(($vpc.IsDefault | not) or ($in | length) > 0)
            | [$p, $a, $r, .VpcId,
                ([.Tags[]? | select(.Key == "Name") | .Value][0] // ""),
                ([.CidrBlockAssociationSet[]? | select(.CidrBlockState.State == "associated") | .CidrBlock] | join(" ")),
                (.IsDefault | tostring), .OwnerId, ($in | length),
                # Kind: the interface type, "ec2" for an instance, else the
                # first word of the description AWS gives managed interfaces
                ($in | map(
                    if .InterfaceType != "interface" then .InterfaceType
                    elif .Attachment.InstanceId then "ec2"
                    else ((.Description // "") | split(" ")[0] | if . == "" then "other" else . end)
                    end)
                    | group_by(.) | map("\(.[0]):\(length)") | join(" ")),
                "ok"]
            | @csv' >>"$out"
    done
    rm -f "$vpcs" "$enis"
    echo "done: $profile ($account)" >&2
}

if [[ "$1" == --one ]]
then
    one_account "$2" "$3" "$4"
    exit 0
fi

if [[ ! -r "$1" ]]
then
    echo "Usage: ${0##*/} profiles.txt > regions.csv" >&2
    exit 1
fi
for cmd in aws jq
do
    if ! command -v "$cmd" >/dev/null 2>&1
    then
        echo "FAIL: $cmd not found" >&2
        exit 1
    fi
done

profiles=()
while IFS= read -r line || [[ -n "$line" ]]
do
    line="${line%$'\r'}"
    line="${line%%#*}"
    # trim leading and trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && profiles+=("$line")
done <"$1"
if (( ${#profiles[@]} == 0 ))
then
    echo "FAIL: no profiles in $1" >&2
    exit 1
fi

# All the SSO profiles share one login, so check it once before starting
if ! aws sts get-caller-identity --profile "${profiles[0]}" >/dev/null 2>&1
then
    if command -v aws-sso-util >/dev/null 2>&1
    then
        echo "SSO login needed; running aws-sso-util login" >&2
        aws-sso-util login >&2 || exit 1
    else
        echo "WARN: ${profiles[0]} can't log in; run aws-sso-util login first" >&2
    fi
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

echo "Scanning ${#profiles[@]} accounts, ${JOBS:-8} at a time" >&2
for i in "${!profiles[@]}"
do
    printf '%s %s\n' "$i" "${profiles[i]}"
done | xargs -n 2 -P "${JOBS:-8}" bash "$0" --one "$tmp"

csv profile account_id region vpc_id vpc_name cidr_blocks is_default owner_id eni_count contents status
for i in "${!profiles[@]}"
do
    cat "$tmp/$i.csv" 2>/dev/null
done
