#!/usr/bin/env bash
# Name: EC2 Instance Deployer
# Author: James Bye
# Purpose: Deploy EC2 instances (general or bastion) with selectable OS, architecture, AMI, storage, and SSM access
# License: MIT License, Copyright (c) 2025 CloudCoreMSP




set -Eeuo pipefail

########################################
# Configuration (defaults)
########################################

INSTANCE_TYPE_DEFAULT_ARM="t4g.nano"         # Cheap ARM-based instance by default
INSTANCE_TYPE_DEFAULT_X86="t3.micro"        # Cheap x86-based instance
OS_DEFAULT="amazon-linux"                   # Internal code, not menu text

PROFILE=""             # Will be chosen interactively
AWS_REGION=""          # Will be chosen interactively
AWS_CLI_COMMON_ARGS=() # Will be set after region selection

SERVER_MODE=""         # "general" or "bastion"
OS_FAMILY=""           # amazon-linux, macos, ubuntu, windows, rhel, suse, debian
ARCH_CHOICE=""         # x86_64 or arm64
AMI_ID=""              # Selected AMI
ROOT_DEVICE_NAME=""    # Root device from AMI
ROOT_VOL_SIZE_DEFAULT="" # Default/min root volume size from AMI
ROOT_VOL_SIZE=""       # Root volume size in GB
ROOT_VOL_TYPE=""       # Root volume type (gp3 etc.)

VPC_ID=""
SUBNET_ID=""
SG_ID=""
KEY_NAME=""

CUSTOMER_TAG=""
ENV_TAG=""
OWNER_TAG=""
COSTCENTER_TAG=""
ROLE_TAG=""

########################################
# Helper functions
########################################

err() {
  echo "[-] ERROR: $*" >&2
  exit 1
}

info() {
  echo "[+] $*"
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local var

  if [[ -n "$default" ]]; then
    read -rp "$prompt [$default]: " var || true
    if [[ -z "${var}" ]]; then
      var="$default"
    fi
  else
    read -rp "$prompt: " var || true
  fi

  echo "$var"
}

########################################
# Profile & Region selection
########################################

select_profile() {
  info "Checking configured AWS profiles..."

  mapfile -t profiles < <(aws configure list-profiles 2>/dev/null || true)

  if ((${#profiles[@]} == 0)); then
    echo "No named profiles found in your AWS config."
    echo "You can use default credentials (env vars / instance role) or configure a profile."
    local choice
    choice="$(prompt_default "Use default credentials? (yes/no)" "yes")"
    if [[ "$choice" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
      PROFILE=""
      info "Using default credentials (no explicit profile)."
      return
    else
      echo "Let's configure a new profile."
      local newprof
      newprof="$(prompt_default "New profile name" "default")"
      aws configure --profile "$newprof"
      PROFILE="$newprof"
      info "Using profile: $PROFILE"
      return
    fi
  fi

  echo "Available AWS profiles:"
  echo "  0) Use default credentials (no profile)"
  local i
  for i in "${!profiles[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${profiles[i]}"
  done
  echo

  # Default selection: first profile (index 1)
  while :; do
    local sel
    sel="$(prompt_default "Select profile by number" "1")"

    if ! [[ "$sel" =~ ^[0-9]+$ ]]; then
      echo "Please enter a number."
      continue
    fi

    if [[ "$sel" -eq 0 ]]; then
      PROFILE=""
      info "Using default credentials (no explicit profile)."
      break
    fi

    local idx=$((sel - 1))
    if ((idx >= 0 && idx < ${#profiles[@]})); then
      PROFILE="${profiles[idx]}"
      info "Using profile: $PROFILE"
      break
    else
      echo "Invalid selection. Try again."
    fi
  done
}

ensure_aws_identity() {
  local args=()
  if [[ -n "$PROFILE" ]]; then
    args+=(--profile "$PROFILE")
  fi

  if aws sts get-caller-identity "${args[@]}" >/dev/null 2>&1; then
    local arn
    arn="$(aws sts get-caller-identity "${args[@]}" --query 'Arn' --output text)"
    info "AWS CLI is authenticated as: $arn"
    return
  fi

  echo
  echo "It looks like your AWS CLI is not authenticated for this profile/credential set."
  echo "You can log in using one of the methods below."
  echo

  PS3="Select an authentication method (1-3): "
  select choice in \
    "Run 'aws configure' for this profile" \
    "Run 'aws sso login' for this profile" \
    "Abort"; do
    case "$REPLY" in
      1)
        echo
        if [[ -n "$PROFILE" ]]; then
          echo "Launching 'aws configure --profile $PROFILE'..."
          aws configure --profile "$PROFILE"
        else
          echo "Launching 'aws configure' (default credentials)..."
          aws configure
        fi
        ;;
      2)
        echo
        if [[ -n "$PROFILE" ]]; then
          echo "Launching 'aws sso login --profile $PROFILE'..."
          aws sso login --profile "$PROFILE"
        else
          echo "Launching 'aws sso login' (no explicit profile)..."
          aws sso login
        fi
        ;;
      3)
        err "No AWS credentials configured. Aborting."
        ;;
      *)
        echo "Please select 1, 2, or 3."
        continue
        ;;
    esac

    if aws sts get-caller-identity "${args[@]}" >/dev/null 2>&1; then
      local arn2
      arn2="$(aws sts get-caller-identity "${args[@]}" --query 'Arn' --output text)"
      info "Authentication successful. Using identity: $arn2"
      return
    else
      echo "Authentication still not working. Try again or choose 'Abort'."
    fi
  done
}

select_region() {
  info "Listing available North American AWS regions..."

  local region_args=()
  if [[ -n "$PROFILE" ]]; then
    region_args+=(--profile "$PROFILE")
  fi

  mapfile -t all_regions < <(
    aws ec2 describe-regions "${region_args[@]}" \
      --all-regions \
      --query 'Regions[].RegionName' \
      --output text
  )

  if ((${#all_regions[@]} == 0)); then
    err "Could not retrieve AWS regions. Check your credentials and permissions."
  fi

  regions=()
  for r in ${all_regions[@]}; do
    if [[ "$r" =~ ^us- || "$r" =~ ^ca- ]]; then
      regions+=("$r")
    fi
  done

  if ((${#regions[@]} == 0)); then
    err "No North American regions available for this account."
  fi

  echo "Available North American regions:"
  local i
  for i in "${!regions[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${regions[i]}"
  done

  local default_region=""
  if [[ -n "$PROFILE" ]]; then
    default_region="$(aws configure get region --profile "$PROFILE" 2>/dev/null || true)"
  else
    default_region="$(aws configure get region 2>/dev/null || true)"
  fi

  local default_index=""
  if [[ -n "$default_region" ]]; then
    for i in "${!regions[@]}"; do
      if [[ "${regions[i]}" == "$default_region" ]]; then
        default_index=$((i + 1))
        break
      fi
    done
  fi

  echo
  if [[ -n "$default_region" && -n "$default_index" ]]; then
    echo "Profile default region (North America): $default_region (option $default_index)."
  fi

  local sel
  if [[ -n "$default_index" ]]; then
    sel="$(prompt_default "Select region by number" "$default_index")"
  else
    sel="$(prompt_default "Select region by number" "1")"
  fi

  if ! [[ "$sel" =~ ^[0-9]+$ ]]; then
    err "Region selection must be a number."
  fi

  local idx=$((sel - 1))
  if ((idx < 0 || idx >= ${#regions[@]})); then
    err "Invalid region selection."
  fi

  AWS_REGION="${regions[idx]}"
  info "Using AWS region: $AWS_REGION"

  AWS_CLI_COMMON_ARGS=(--region "$AWS_REGION")
  if [[ -n "$PROFILE" ]]; then
    AWS_CLI_COMMON_ARGS+=(--profile "$PROFILE")
  fi
}

########################################
# Server mode & OS/AMI selection
########################################

select_server_mode() {
  echo
  echo "What type of EC2 instance would you like to launch:"
  echo "  1) General Use Server"
  echo "  2) Bastion Server"
  echo

  while :; do
    local choice
    choice="$(prompt_default 'Select an option (1-2)' '1')"
    case "$choice" in
      1)
        SERVER_MODE="general"
        info "Server mode: General Use Server"
        break
        ;;
      2)
        SERVER_MODE="bastion"
        info "Server mode: Bastion Server"
        break
        ;;
      *)
        echo "Please choose 1 or 2."
        ;;
    esac
  done
}

select_os_family() {
  echo
  echo "Choose an OS:"
  echo "  1) Amazon Linux"
  echo "  2) macOS"
  echo "  3) Ubuntu"
  echo "  4) Windows Server"
  echo "  5) Red Hat Enterprise Linux"
  echo "  6) SUSE Linux"
  echo "  7) Debian"
  echo

  while :; do
    local choice
    choice="$(prompt_default 'Select an OS (1-7)' '1')"
    case "$choice" in
      1) OS_FAMILY="amazon-linux"; break ;;
      2) OS_FAMILY="macos"; break ;;
      3) OS_FAMILY="ubuntu"; break ;;
      4) OS_FAMILY="windows"; break ;;
      5) OS_FAMILY="rhel"; break ;;
      6) OS_FAMILY="suse"; break ;;
      7) OS_FAMILY="debian"; break ;;
      *) echo "Please choose a number between 1 and 7." ;;
    esac
  done

  info "Selected OS family: $OS_FAMILY"
}

select_architecture() {
  echo
  echo "Choose architecture:"
  echo "  1) x86_64"
  echo "  2) arm64"
  echo

  while :; do
    local choice
    choice="$(prompt_default 'Select an architecture (1-2)' '1')"
    case "$choice" in
      1) ARCH_CHOICE="x86_64"; break ;;
      2) ARCH_CHOICE="arm64"; break ;;
      *) echo "Please choose 1 or 2." ;;
    esac
  done

  info "Selected architecture: $ARCH_CHOICE"
}

set_ami_filters_for_os() {
  # Sets AMI_OWNER and AMI_NAME_FILTER (may be empty)
  case "$OS_FAMILY" in
    amazon-linux)
      AMI_OWNER="amazon"
      AMI_NAME_FILTER="al2023-ami-*-kernel-6.1-*"
      ;;
    ubuntu)
      AMI_OWNER="099720109477"  # Canonical
      AMI_NAME_FILTER="ubuntu/images/hvm-ssd-gp3/ubuntu-*-24.04-*-server-*"
      ;;
    windows)
      AMI_OWNER="amazon"
      AMI_NAME_FILTER="Windows_Server-*-English-Full-Base-*"
      ;;
    rhel)
      AMI_OWNER="309956199498"  # Red Hat
      AMI_NAME_FILTER=""
      ;;
    suse)
      AMI_OWNER="013907871322"  # SUSE
      AMI_NAME_FILTER=""
      ;;
    debian)
      AMI_OWNER="136693071363"  # Debian
      AMI_NAME_FILTER=""
      ;;
    macos)
      AMI_OWNER="amazon"
      AMI_NAME_FILTER="amzn-ec2-macos-*"
      ;;
    *)
      err "Unsupported OS family: $OS_FAMILY"
      ;;
  esac
}

select_ami() {
  set_ami_filters_for_os

  info "Searching for AMIs for OS '$OS_FAMILY' with architecture '$ARCH_CHOICE' in $AWS_REGION..."

  local filters=(
    "Name=architecture,Values=${ARCH_CHOICE}"
    "Name=root-device-type,Values=ebs"
    "Name=virtualization-type,Values=hvm"
  )
  if [[ -n "$AMI_NAME_FILTER" ]]; then
    filters+=("Name=name,Values=${AMI_NAME_FILTER}")
  fi

  mapfile -t AMI_IDS < <(
    aws ec2 describe-images "${AWS_CLI_COMMON_ARGS[@]}" \
      --owners "$AMI_OWNER" \
      --filters "${filters[@]}" \
      --query 'Images[?Public==`true`] | sort_by(@,&CreationDate) | reverse(@)[:10].ImageId' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  mapfile -t AMI_NAMES < <(
    aws ec2 describe-images "${AWS_CLI_COMMON_ARGS[@]}" \
      --owners "$AMI_OWNER" \
      --filters "${filters[@]}" \
      --query 'Images[?Public==`true`] | sort_by(@,&CreationDate) | reverse(@)[:10].Name' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  mapfile -t AMI_DATES < <(
    aws ec2 describe-images "${AWS_CLI_COMMON_ARGS[@]}" \
      --owners "$AMI_OWNER" \
      --filters "${filters[@]}" \
      --query 'Images[?Public==`true`] | sort_by(@,&CreationDate) | reverse(@)[:10].CreationDate' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  if ((${#AMI_IDS[@]} == 0)); then
    err "No AMIs found for OS '$OS_FAMILY' and architecture '$ARCH_CHOICE' in region $AWS_REGION."
  fi

  echo
  echo "Available AMIs (newest first):"
  local i
  for i in "${!AMI_IDS[@]}"; do
    printf "  %d) %s | %s | %s\n" \
      "$((i + 1))" "${AMI_IDS[i]}" "${AMI_NAMES[i]:-<no-name>}" "${AMI_DATES[i]:-}"
  done
  echo

  while :; do
    local choice
    choice="$(prompt_default 'Select an AMI by number' '1')"
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      echo "Please enter a valid number."
      continue
    fi
    local idx=$((choice - 1))
    if ((idx >= 0 && idx < ${#AMI_IDS[@]})); then
      AMI_ID="${AMI_IDS[idx]}"
      info "Selected AMI: $AMI_ID (${AMI_NAMES[idx]:-})"
      break
    else
      echo "Number out of range. Please choose a valid index."
    fi
  done

  # Root device
  ROOT_DEVICE_NAME="$(
    aws ec2 describe-images "${AWS_CLI_COMMON_ARGS[@]}" \
      --image-ids "$AMI_ID" \
      --query 'Images[0].RootDeviceName' \
      --output text 2>/dev/null || echo "/dev/xvda"
  )"
  info "AMI root device: $ROOT_DEVICE_NAME"

  # Root volume default size from AMI snapshot
  ROOT_VOL_SIZE_DEFAULT="$(
    aws ec2 describe-images "${AWS_CLI_COMMON_ARGS[@]}" \
      --image-ids "$AMI_ID" \
      --query "Images[0].BlockDeviceMappings[?DeviceName=='${ROOT_DEVICE_NAME}'].Ebs.VolumeSize | [0]" \
      --output text 2>/dev/null || echo "20"
  )"

  if [[ "$ROOT_VOL_SIZE_DEFAULT" == "None" || -z "$ROOT_VOL_SIZE_DEFAULT" ]]; then
    ROOT_VOL_SIZE_DEFAULT="20"
  fi

  info "Detected AMI root volume size: ${ROOT_VOL_SIZE_DEFAULT} GB (minimum)"
}

########################################
# VPC / Subnet / Security Group
########################################

select_or_create_vpc() {
  info "Listing existing VPCs in region $AWS_REGION..."

  aws ec2 describe-vpcs "${AWS_CLI_COMMON_ARGS[@]}" \
    --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
    --output table || echo "No VPCs found or unable to list VPCs."

  mapfile -t VPC_IDS < <(
    aws ec2 describe-vpcs "${AWS_CLI_COMMON_ARGS[@]}" \
      --query 'Vpcs[].VpcId' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  echo
  if ((${#VPC_IDS[@]} > 0)); then
    echo "Indexed VPC list:"
    local i
    for i in "${!VPC_IDS[@]}"; do
      printf "  %d) %s\n" "$((i + 1))" "${VPC_IDS[i]}"
    done
    echo
    echo "You can:"
    echo "  - Enter a number from the list above"
    echo "  - Enter an exact VPC ID (vpc-...)"
    echo "  - Type 'new' to create a new VPC"
    echo
  else
    echo "No existing VPCs were found. You must create a new one."
  fi

  while :; do
    read -rp "Select VPC (number, 'new', or VPC ID): " vpc_choice

    if [[ "$vpc_choice" == "new" ]]; then
      create_new_vpc
      VPC_ID="$NEW_VPC_ID"
      break
    fi

    if [[ "$vpc_choice" =~ ^[0-9]+$ ]] && ((${#VPC_IDS[@]} > 0)); then
      local idx=$((vpc_choice - 1))
      if ((idx >= 0 && idx < ${#VPC_IDS[@]})); then
        VPC_ID="${VPC_IDS[idx]}"
        info "Using existing VPC (by index): $VPC_ID"
        break
      else
        echo "Number out of range. Please choose a valid index."
        continue
      fi
    fi

    if [[ "$vpc_choice" =~ ^vpc- ]]; then
      local exists
      exists="$(
        aws ec2 describe-vpcs "${AWS_CLI_COMMON_ARGS[@]}" \
          --vpc-ids "$vpc_choice" \
          --query 'Vpcs[0].VpcId' \
          --output text 2>/dev/null || true
      )"
      if [[ "$exists" == "$vpc_choice" ]]; then
        VPC_ID="$vpc_choice"
        info "Using existing VPC (by ID): $VPC_ID"
        break
      else
        echo "VPC $vpc_choice not found in this region. Please try again."
        continue
      fi
    fi

    echo "Invalid input. Please enter a number, 'new', or a valid VPC ID (vpc-...)."
  done
}

create_new_vpc() {
  echo
  info "Creating a new VPC..."

  local cidr name_default
  cidr="$(prompt_default 'CIDR block for new VPC' '10.0.0.0/16')"

  if [[ "$SERVER_MODE" == "bastion" ]]; then
    name_default="bastion-vpc"
  else
    name_default="server-vpc"
  fi
  local name
  name="$(prompt_default 'Name tag for new VPC' "$name_default")"

  NEW_VPC_ID="$(
    aws ec2 create-vpc "${AWS_CLI_COMMON_ARGS[@]}" \
      --cidr-block "$cidr" \
      --query 'Vpc.VpcId' \
      --output text
  )" || err "Failed to create VPC."

  aws ec2 create-tags "${AWS_CLI_COMMON_ARGS[@]}" \
    --resources "$NEW_VPC_ID" \
    --tags "Key=Name,Value=${name}" >/dev/null

  aws ec2 modify-vpc-attribute "${AWS_CLI_COMMON_ARGS[@]}" \
    --vpc-id "$NEW_VPC_ID" \
    --enable-dns-support "{\"Value\":true}" >/dev/null 2>&1 || true

  aws ec2 modify-vpc-attribute "${AWS_CLI_COMMON_ARGS[@]}" \
    --vpc-id "$NEW_VPC_ID" \
    --enable-dns-hostnames "{\"Value\":true}" >/dev/null 2>&1 || true

  info "Created VPC $NEW_VPC_ID with CIDR $cidr and Name tag '$name'."

  cat <<EOF

NOTE: This script does NOT automatically create an Internet Gateway,
route tables, or NAT gateways for the new VPC.

For SSM/SSH to work, instances typically need egress to the internet or
VPC endpoints for SSM services. You can:
  - Attach an Internet Gateway + route table for public subnets, or
  - Create VPC Interface Endpoints for SSM/EC2 messages, etc., or
  - Add NAT gateway(s) for private subnets.

EOF
}

select_or_create_subnet() {
  info "Listing existing subnets in VPC $VPC_ID..."

  aws ec2 describe-subnets "${AWS_CLI_COMMON_ARGS[@]}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[].{SubnetId:SubnetId,Cidr:CidrBlock,Az:AvailabilityZone,Name:Tags[?Key==`Name`]|[0].Value}' \
    --output table || echo "No subnets found or unable to list subnets."

  mapfile -t SUBNET_IDS < <(
    aws ec2 describe-subnets "${AWS_CLI_COMMON_ARGS[@]}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'Subnets[].SubnetId' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  echo
  if ((${#SUBNET_IDS[@]} > 0)); then
    echo "Indexed Subnet list:"
    local i
    for i in "${!SUBNET_IDS[@]}"; do
      printf "  %d) %s\n" "$((i + 1))" "${SUBNET_IDS[i]}"
    done
    echo
    echo "You can:"
    echo "  - Enter a number from the list above"
    echo "  - Enter an exact Subnet ID (subnet-...)"
    echo "  - Type 'new' to create a new subnet"
    echo
  else
    echo "No existing subnets were found in this VPC. You must create a new one."
  fi

  while :; do
    read -rp "Select Subnet (number, 'new', or Subnet ID): " subnet_choice

    if [[ "$subnet_choice" == "new" ]]; then
      create_new_subnet
      SUBNET_ID="$NEW_SUBNET_ID"
      break
    fi

    if [[ "$subnet_choice" =~ ^[0-9]+$ ]] && ((${#SUBNET_IDS[@]} > 0)); then
      local idx=$((subnet_choice - 1))
      if ((idx >= 0 && idx < ${#SUBNET_IDS[@]})); then
        SUBNET_ID="${SUBNET_IDS[idx]}"
        info "Using existing subnet (by index): $SUBNET_ID"
        break
      else
        echo "Number out of range. Please choose a valid index."
        continue
      fi
    fi

    if [[ "$subnet_choice" =~ ^subnet- ]]; then
      local exists
      exists="$(
        aws ec2 describe-subnets "${AWS_CLI_COMMON_ARGS[@]}" \
          --subnet-ids "$subnet_choice" \
          --query 'Subnets[0].SubnetId' \
          --output text 2>/dev/null || true
      )"
      if [[ "$exists" == "$subnet_choice" ]]; then
        SUBNET_ID="$subnet_choice"
        info "Using existing subnet (by ID): $SUBNET_ID"
        break
      else
        echo "Subnet $subnet_choice not found in VPC $VPC_ID. Please try again."
        continue
      fi
    fi

    echo "Invalid input. Please enter a number, 'new', or a valid Subnet ID (subnet-...)."
  done
}

create_new_subnet() {
  echo
  info "Creating a new subnet in VPC $VPC_ID..."

  local cidr name_default
  cidr="$(prompt_default 'CIDR block for new subnet' '10.0.1.0/24')"

  if [[ "$SERVER_MODE" == "bastion" ]]; then
    name_default="bastion-subnet"
  else
    name_default="server-subnet"
  fi
  local name
  name="$(prompt_default 'Name tag for new subnet' "$name_default")"

  info "Available Availability Zones in region $AWS_REGION:"
  aws ec2 describe-availability-zones "${AWS_CLI_COMMON_ARGS[@]}" \
    --query 'AvailabilityZones[].ZoneName' \
    --output text

  local az
  az="$(prompt_default 'Availability Zone for new subnet' "${AWS_REGION}a")"

  NEW_SUBNET_ID="$(
    aws ec2 create-subnet "${AWS_CLI_COMMON_ARGS[@]}" \
      --vpc-id "$VPC_ID" \
      --cidr-block "$cidr" \
      --availability-zone "$az" \
      --query 'Subnet.SubnetId' \
      --output text
  )" || err "Failed to create subnet."

  aws ec2 create-tags "${AWS_CLI_COMMON_ARGS[@]}" \
    --resources "$NEW_SUBNET_ID" \
    --tags "Key=Name,Value=${name}" >/dev/null

  local map_public
  map_public="$(prompt_default 'Map public IPs on launch for this subnet? (yes/no)' 'yes')"
  if [[ "$map_public" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    aws ec2 modify-subnet-attribute "${AWS_CLI_COMMON_ARGS[@]}" \
      --subnet-id "$NEW_SUBNET_ID" \
      --map-public-ip-on-launch >/dev/null
    info "Enabled automatic public IP assignment for subnet $NEW_SUBNET_ID."
  else
    info "Leaving automatic public IP assignment disabled for subnet $NEW_SUBNET_ID."
  fi

  info "Created subnet $NEW_SUBNET_ID with CIDR $cidr in AZ $az and Name tag '$name'."

  cat <<EOF

NOTE: This script does NOT automatically configure route tables for the new subnet.
Ensure there is an appropriate route table associated with this subnet if you need
internet access (for SSM, updates, etc.).

EOF
}

select_or_create_sg() {
  info "Listing existing security groups in VPC $VPC_ID..."

  aws ec2 describe-security-groups "${AWS_CLI_COMMON_ARGS[@]}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Description:Description}' \
    --output table || echo "No security groups found or unable to list."

  mapfile -t SG_IDS < <(
    aws ec2 describe-security-groups "${AWS_CLI_COMMON_ARGS[@]}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'SecurityGroups[].GroupId' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  mapfile -t SG_NAMES < <(
    aws ec2 describe-security-groups "${AWS_CLI_COMMON_ARGS[@]}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'SecurityGroups[].GroupName' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  echo
  if ((${#SG_IDS[@]} > 0)); then
    echo "Indexed Security Group list:"
    local i
    for i in "${!SG_IDS[@]}"; do
      local name="${SG_NAMES[i]:-}"
      printf "  %d) %s (%s)\n" "$((i + 1))" "${SG_IDS[i]}" "${name}"
    done
    echo
    echo "You can:"
    echo "  - Enter a number from the list above"
    echo "  - Enter an exact Security Group ID (sg-...)"
    echo "  - Type 'new' to create a new security group"
    echo
  else
    echo "No existing security groups were found in this VPC. You must create a new one."
  fi

  while :; do
    read -rp "Select Security Group (number, 'new', or SG ID): " sg_choice

    if [[ "$sg_choice" == "new" ]]; then
      create_new_sg
      SG_ID="$NEW_SG_ID"
      break
    fi

    if [[ "$sg_choice" =~ ^[0-9]+$ ]] && ((${#SG_IDS[@]} > 0)); then
      local idx=$((sg_choice - 1))
      if ((idx >= 0 && idx < ${#SG_IDS[@]})); then
        SG_ID="${SG_IDS[idx]}"
        info "Using existing Security Group (by index): $SG_ID"
        break
      else
        echo "Number out of range. Please choose a valid index."
        continue
      fi
    fi

    if [[ "$sg_choice" =~ ^sg- ]]; then
      local exists
      exists="$(
        aws ec2 describe-security-groups "${AWS_CLI_COMMON_ARGS[@]}" \
          --group-ids "$sg_choice" \
          --query 'SecurityGroups[0].GroupId' \
          --output text 2>/dev/null || true
      )"
      if [[ "$exists" == "$sg_choice" ]]; then
        SG_ID="$sg_choice"
        info "Using existing Security Group (by ID): $SG_ID"
        break
      else
        echo "Security Group $sg_choice not found in VPC $VPC_ID. Please try again."
        continue
      fi
    fi

    echo "Invalid input. Please enter a number, 'new', or a valid Security Group ID (sg-...)."
  done
}

create_new_sg() {
  echo
  info "Creating a new Security Group in VPC $VPC_ID..."

  local name_default desc_default
  if [[ "$SERVER_MODE" == "bastion" ]]; then
    name_default="bastion-ssm-sg"
    desc_default="Security group for SSM-based bastion (no inbound by default)"
  else
    name_default="generic-ec2-sg"
    desc_default="Generic EC2 security group (no inbound by default)"
  fi

  local name desc
  name="$(prompt_default 'Security Group name' "$name_default")"
  desc="$(prompt_default 'Security Group description' "$desc_default")"

  NEW_SG_ID="$(
    aws ec2 create-security-group "${AWS_CLI_COMMON_ARGS[@]}" \
      --group-name "$name" \
      --description "$desc" \
      --vpc-id "$VPC_ID" \
      --query 'GroupId' \
      --output text
  )" || err "Failed to create Security Group."

  info "Created Security Group $NEW_SG_ID"

  local sg_role_tag
  if [[ "$SERVER_MODE" == "bastion" ]]; then
    sg_role_tag="Bastion-SG"
  else
    sg_role_tag="EC2-SG"
  fi

  local TAG_ARGS=(--resources "$NEW_SG_ID" --tags "Key=Name,Value=${name}" "Key=Role,Value=${sg_role_tag}")
  aws ec2 create-tags "${AWS_CLI_COMMON_ARGS[@]}" "${TAG_ARGS[@]}" >/dev/null

  cat <<EOF

NOTE: This Security Group currently has no inbound rules and default outbound.
For SSM-only management, this is usually fine (outbound to SSM endpoints or internet).
If you plan to use SSH, RDP, HTTP(S), or other protocols, add inbound rules as appropriate.

EOF
}

########################################
# Key pair management
########################################

keypair_exists() {
  local name="$1"
  aws ec2 describe-key-pairs "${AWS_CLI_COMMON_ARGS[@]}" \
    --key-names "$name" \
    --query 'KeyPairs[0].KeyName' \
    --output text >/dev/null 2>&1
}

create_new_keypair() {
  local base_dir="${HOME}/.aws/keypairs"
  mkdir -p "$base_dir" || err "Failed to create keypair directory: $base_dir"

  local default_prefix
  if [[ "$SERVER_MODE" == "bastion" ]]; then
    default_prefix="bastion"
  else
    default_prefix="server"
  fi

  local default_name="${default_prefix}-$(date +%Y%m%d-%H%M%S)"
  local kp_name
  while :; do
    kp_name="$(prompt_default 'New key pair name' "$default_name")"
    if [[ -z "$kp_name" ]]; then
      echo "Key pair name cannot be empty."
      continue
    fi

    if keypair_exists "$kp_name"; then
      echo "A key pair named '$kp_name' already exists in region $AWS_REGION."
      local reuse
      reuse="$(prompt_default "Use existing key pair '$kp_name' without creating a new file? (yes/no)" "yes")"
      if [[ "$reuse" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        KEY_NAME="$kp_name"
        info "Using existing key pair: $KEY_NAME (no new .pem file created; AWS does not expose private key again)."
        return
      else
        echo "Choose a different key pair name."
        continue
      fi
    fi

    local key_file="${base_dir}/${kp_name}.pem"
    if [[ -e "$key_file" ]]; then
      local overwrite
      overwrite="$(prompt_default "File $key_file already exists. Overwrite? (yes/no)" "no")"
      if ! [[ "$overwrite" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        echo "Choose a different key pair name."
        continue
      fi
    fi

    info "Creating new key pair '$kp_name' in region $AWS_REGION and saving to $key_file"

    aws ec2 create-key-pair "${AWS_CLI_COMMON_ARGS[@]}" \
      --key-name "$kp_name" \
      --query 'KeyMaterial' \
      --output text > "$key_file" || err "Failed to create key pair '$kp_name'."

    chmod 600 "$key_file" || echo "Warning: failed to set permissions on $key_file"

    KEY_NAME="$kp_name"
    info "New key pair '$KEY_NAME' created."
    echo "Private key saved to: $key_file"
    echo "Keep this file safe; it cannot be retrieved again from AWS."
    return
  done
}

select_existing_keypair() {
  info "Listing available EC2 key pairs in region $AWS_REGION..."

  mapfile -t KP_NAMES < <(
    aws ec2 describe-key-pairs "${AWS_CLI_COMMON_ARGS[@]}" \
      --query 'KeyPairs[].KeyName' \
      --output text 2>/dev/null | tr '\t' '\n' || true
  )

  if ((${#KP_NAMES[@]} == 0)); then
    echo "No key pairs exist in region $AWS_REGION."
    return 1
  fi

  echo "Available key pairs in $AWS_REGION:"
  local i
  for i in "${!KP_NAMES[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${KP_NAMES[i]}"
  done
  echo

  while :; do
    read -rp "Select key pair by number: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      echo "Please enter a valid number."
      continue
    fi

    local idx=$((choice - 1))
    if ((idx >= 0 && idx < ${#KP_NAMES[@]})); then
      KEY_NAME="${KP_NAMES[idx]}"
      info "Using key pair: $KEY_NAME"
      return 0
    else
      echo "Number out of range. Please choose a valid index."
    fi
  done
}

handle_keypair_selection() {
  echo
  echo "SSH key pair options:"
  echo "  1) Attach an existing SSH key pair"
  echo "  2) Create a new SSH key pair"
  echo "  3) Do not attach an SSH key pair"
  echo

  while :; do
    local choice
    choice="$(prompt_default 'Select an option (1-3)' '3')"

    case "$choice" in
      1)
        if ! select_existing_keypair; then
          echo
          echo "No existing key pairs are available in region $AWS_REGION."
          local fallback
          fallback="$(prompt_default 'Would you like to create a new SSH key pair instead? (yes/no)' 'yes')"
          if [[ "$fallback" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
            create_new_keypair
          else
            KEY_NAME=""
            info "No key pair will be attached."
          fi
        fi
        break
        ;;
      2)
        create_new_keypair
        break
        ;;
      3)
        KEY_NAME=""
        info "No key pair will be attached."
        break
        ;;
      *)
        echo "Please choose 1, 2, or 3."
        ;;
    esac
  done
}

########################################
# Initial checks & global inputs
########################################

if ! command -v aws >/dev/null 2>&1; then
  err "aws CLI not found. Please install and configure AWS CLI v2 first."
fi

select_profile
ensure_aws_identity
select_region
select_server_mode
select_os_family
select_architecture
select_ami

echo
# Storage configuration (use AMI minimum as default)
ROOT_VOL_SIZE="$(prompt_default 'Root volume size (GB)' "$ROOT_VOL_SIZE_DEFAULT")"

if ! [[ "$ROOT_VOL_SIZE" =~ ^[0-9]+$ ]]; then
  err "Root volume size must be a positive integer."
fi

# Enforce minimum: cannot be smaller than snapshot size
if (( ROOT_VOL_SIZE < ROOT_VOL_SIZE_DEFAULT )); then
  echo "Requested root volume size (${ROOT_VOL_SIZE} GB) is smaller than the AMI snapshot minimum (${ROOT_VOL_SIZE_DEFAULT} GB)."
  echo "Using ${ROOT_VOL_SIZE_DEFAULT} GB instead."
  ROOT_VOL_SIZE="$ROOT_VOL_SIZE_DEFAULT"
fi

ROOT_VOL_TYPE="$(prompt_default 'Root volume type (gp3/gp2/io1/io2/st1/sc1/standard)' 'gp3')"

echo
echo "=== EC2 Instance Deployer ==="

# Instance name
INSTANCE_NAME_DEFAULT="$([[ "$SERVER_MODE" == "bastion" ]] && echo "bastion-$(date +%Y%m%d-%H%M%S)" || echo "server-$(date +%Y%m%d-%H%M%S)")"
INSTANCE_NAME="$(prompt_default 'EC2 instance name' "$INSTANCE_NAME_DEFAULT")"

# Tags
CUSTOMER_TAG="$(prompt_default 'Customer tag (blank to skip)' '')"
ENV_TAG="$(prompt_default 'Environment tag (e.g. prod/dev, blank to skip)' '')"
OWNER_TAG="$(prompt_default 'Owner tag (blank to skip)' '')"
COSTCENTER_TAG="$(prompt_default 'CostCenter tag (blank to skip)' '')"

ROLE_TAG_DEFAULT="$([[ "$SERVER_MODE" == "bastion" ]] && echo "Bastion" || echo "Server")"
ROLE_TAG="$(prompt_default 'Role tag (e.g. web, db, bastion)' "$ROLE_TAG_DEFAULT")"

# Instance type default based on architecture
if [[ "$ARCH_CHOICE" == "arm64" ]]; then
  INSTANCE_TYPE_DEFAULT="$INSTANCE_TYPE_DEFAULT_ARM"
else
  INSTANCE_TYPE_DEFAULT="$INSTANCE_TYPE_DEFAULT_X86"
fi

INSTANCE_TYPE="$(prompt_default 'Instance type' "$INSTANCE_TYPE_DEFAULT")"

# Key pair handling
handle_keypair_selection

# Public IP default: yes (per request)
ASSOC_PUBLIC_IP_DEFAULT="yes"
ASSOC_PUBLIC_IP="$(prompt_default 'Associate public IP to instance ENI? (yes/no)' "$ASSOC_PUBLIC_IP_DEFAULT")"

########################################
# Network selection
########################################

select_or_create_vpc
select_or_create_subnet
select_or_create_sg

########################################
# Summary & confirmation
########################################

echo
echo "=== EC2 Deployment Summary ==="
echo "Profile:        ${PROFILE:-<default>}"
echo "Region:         $AWS_REGION"
echo "Server Mode:    $SERVER_MODE"
echo "OS Family:      $OS_FAMILY"
echo "Architecture:   $ARCH_CHOICE"
echo "AMI ID:         $AMI_ID"
echo "Instance Type:  $INSTANCE_TYPE"
echo "Instance Name:  $INSTANCE_NAME"
echo "VPC ID:         $VPC_ID"
echo "Subnet ID:      $SUBNET_ID"
echo "Security Group: $SG_ID"
echo "Public IP:      $ASSOC_PUBLIC_IP"
echo "SSH Key Pair:   ${KEY_NAME:-<none>}"
echo "Root Volume:    ${ROOT_VOL_SIZE} GB (min ${ROOT_VOL_SIZE_DEFAULT} GB), type ${ROOT_VOL_TYPE}, device ${ROOT_DEVICE_NAME}"
echo "Tags:"
echo "  Role:         ${ROLE_TAG:-<none>}"
echo "  Customer:     ${CUSTOMER_TAG:-<none>}"
echo "  Environment:  ${ENV_TAG:-<none>}"
echo "  Owner:        ${OWNER_TAG:-<none>}"
echo "  CostCenter:   ${COSTCENTER_TAG:-<none>}"
echo

PROCEED="$(prompt_default 'Proceed with EC2 deployment? (yes/no)' 'yes')"
if ! [[ "$PROCEED" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
  info "Aborting deployment per user request."
  exit 0
fi

########################################
# IAM Role / Instance Profile for SSM
########################################

if [[ "$SERVER_MODE" == "bastion" ]]; then
  SSM_ROLE_NAME="EC2BastionSSMRole"
  SSM_INSTANCE_PROFILE_NAME="EC2BastionSSMInstanceProfile"
else
  SSM_ROLE_NAME="EC2SSMRole"
  SSM_INSTANCE_PROFILE_NAME="EC2SSMInstanceProfile"
fi

# 1) Ensure role exists
if ! aws iam get-role "${AWS_CLI_COMMON_ARGS[@]}" --role-name "$SSM_ROLE_NAME" >/dev/null 2>&1; then
  info "Creating IAM role: $SSM_ROLE_NAME"

  aws iam create-role "${AWS_CLI_COMMON_ARGS[@]}" \
    --role-name "$SSM_ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null

  aws iam attach-role-policy "${AWS_CLI_COMMON_ARGS[@]}" \
    --role-name "$SSM_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore >/dev/null
else
  info "IAM role $SSM_ROLE_NAME already exists, reusing."
fi

# 2) Ensure instance profile exists and has the role attached
if ! aws iam get-instance-profile "${AWS_CLI_COMMON_ARGS[@]}" --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  info "Creating instance profile: $SSM_INSTANCE_PROFILE_NAME"

  aws iam create-instance-profile "${AWS_CLI_COMMON_ARGS[@]}" \
    --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" >/dev/null

  aws iam add-role-to-instance-profile "${AWS_CLI_COMMON_ARGS[@]}" \
    --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" \
    --role-name "$SSM_ROLE_NAME" >/dev/null
else
  info "Instance profile $SSM_INSTANCE_PROFILE_NAME already exists, reusing."

  ATTACHED_ROLE="$(
    aws iam get-instance-profile "${AWS_CLI_COMMON_ARGS[@]}" \
      --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" \
      --query 'InstanceProfile.Roles[0].RoleName' \
      --output text 2>/dev/null || true
  )"

  if [[ "$ATTACHED_ROLE" != "$SSM_ROLE_NAME" ]]; then
    info "Attaching role $SSM_ROLE_NAME to instance profile $SSM_INSTANCE_PROFILE_NAME"
    aws iam add-role-to-instance-profile "${AWS_CLI_COMMON_ARGS[@]}" \
      --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" \
      --role-name "$SSM_ROLE_NAME" >/dev/null
  fi
fi

# 3) Wait for IAM eventual consistency: profile + correct role attachment
info "Waiting for IAM instance profile '$SSM_INSTANCE_PROFILE_NAME' and role attachment to propagate..."

ATTACHED_ROLE=""
for attempt in {1..20}; do
  ATTACHED_ROLE="$(
    aws iam get-instance-profile "${AWS_CLI_COMMON_ARGS[@]}" \
      --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" \
      --query 'InstanceProfile.Roles[0].RoleName' \
      --output text 2>/dev/null || true
  )"

  if [[ "$ATTACHED_ROLE" == "$SSM_ROLE_NAME" ]]; then
    info "Instance profile and role attachment visible (attempt $attempt)."
    break
  fi

  info "Instance profile not fully ready yet (attempt $attempt). Sleeping 3s..."
  sleep 3
done

if [[ "$ATTACHED_ROLE" != "$SSM_ROLE_NAME" ]]; then
  echo "Warning: after waiting, instance profile '$SSM_INSTANCE_PROFILE_NAME' does not show role '$SSM_ROLE_NAME'."
  echo "EC2 RunInstances may still fail with Invalid IAM Instance Profile if IAM propagation is slow."
fi

########################################
# Network & storage options for launch
########################################

ASSOC_PUBLIC_IP_FLAG="false"
if [[ "$ASSOC_PUBLIC_IP" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
  ASSOC_PUBLIC_IP_FLAG="true"
fi

# Build dynamic tags for the instance
TAGS="[{Key=Name,Value=${INSTANCE_NAME}},{Key=Role,Value=${ROLE_TAG}},{Key=OS,Value=${OS_FAMILY}},{Key=ServerMode,Value=${SERVER_MODE}}"

if [[ -n "$CUSTOMER_TAG" ]]; then
  TAGS+=",{Key=Customer,Value=${CUSTOMER_TAG}}"
fi
if [[ -n "$ENV_TAG" ]]; then
  TAGS+=",{Key=Environment,Value=${ENV_TAG}}"
fi
if [[ -n "$OWNER_TAG" ]]; then
  TAGS+=",{Key=Owner,Value=${OWNER_TAG}}"
fi
if [[ -n "$COSTCENTER_TAG" ]]; then
  TAGS+=",{Key=CostCenter,Value=${COSTCENTER_TAG}}"
fi

TAGS+="]"

########################################
# Launch the instance
########################################

info "Launching EC2 instance..."

RUN_INST_ARGS=(
  "${AWS_CLI_COMMON_ARGS[@]}"
  --image-id "$AMI_ID"
  --instance-type "$INSTANCE_TYPE"
  --iam-instance-profile "Name=${SSM_INSTANCE_PROFILE_NAME}"
  --network-interfaces "DeviceIndex=0,SubnetId=${SUBNET_ID},Groups=${SG_ID},AssociatePublicIpAddress=${ASSOC_PUBLIC_IP_FLAG}"
  --tag-specifications "ResourceType=instance,Tags=${TAGS}"
  --block-device-mappings "DeviceName=${ROOT_DEVICE_NAME},Ebs={VolumeSize=${ROOT_VOL_SIZE},VolumeType=${ROOT_VOL_TYPE},DeleteOnTermination=true}"
  --count 1
)

if [[ -n "$KEY_NAME" ]]; then
  RUN_INST_ARGS+=(--key-name "$KEY_NAME")
fi

INSTANCE_ID="$(
  aws ec2 run-instances "${RUN_INST_ARGS[@]}" \
    --query 'Instances[0].InstanceId' \
    --output text
)"

info "Launched instance: $INSTANCE_ID"

info "Waiting for instance to reach 'running' state..."
aws ec2 wait instance-running "${AWS_CLI_COMMON_ARGS[@]}" --instance-ids "$INSTANCE_ID"

info "EC2 instance is running."
info "Instance ID: $INSTANCE_ID"
info "Name tag:    $INSTANCE_NAME"

########################################
# Output how to connect
########################################

cat <<EOF

=== EC2 Instance Deployed ===

Profile:        ${PROFILE:-<default>}
Instance ID:    $INSTANCE_ID
Name Tag:       $INSTANCE_NAME
Region:         $AWS_REGION
Server Mode:    $SERVER_MODE
OS Family:      $OS_FAMILY
Architecture:   $ARCH_CHOICE
AMI ID:         $AMI_ID
Instance Type:  $INSTANCE_TYPE
VPC ID:         $VPC_ID
Subnet ID:      $SUBNET_ID
Security Group: $SG_ID
SSH Key Pair:   ${KEY_NAME:-<none>}
Root Volume:    ${ROOT_VOL_SIZE} GB (min ${ROOT_VOL_SIZE_DEFAULT} GB), type ${ROOT_VOL_TYPE}, device ${ROOT_DEVICE_NAME}

If you created a new key pair, its private key file was saved under:

  ~/.aws/keypairs/<key-name>.pem

To connect via SSM Session Manager (recommended):

  aws ssm start-session \\
    ${PROFILE:+--profile "$PROFILE"} \\
    --target "$INSTANCE_ID" \\
    --region "$AWS_REGION"

(Ensure your IAM user/role has permission: ssm:StartSession and the instance has
AmazonSSMManagedInstanceCore role attached, which this script configured.)

If you enabled SSH and a public IP, you can also connect via normal SSH using that key.

EOF
