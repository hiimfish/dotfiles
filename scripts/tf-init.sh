#!/bin/bash

# 用來在 foo-infra 之前建立需要的資源

set -e  # 出錯即停止
set -u  # 使用未定義變數時報錯

# === Function: 取得 AWS profile ===
get_aws_profile() {
  local AWS_CONFIG_FILE="$HOME/.aws/credentials"
  
  echo "🔍 可用的 AWS profiles：" >&2
  local PROFILES=($(grep '^\[' "$AWS_CONFIG_FILE" | sed 's/^\[\(.*\)\]$/\1/' | grep -v '^default$'))
  
  if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "❌ 沒有發現非 default 的 AWS profiles，請先設定 ~/.aws/credentials" >&2
    exit 1
  fi
  
  echo >&2
  local PROFILE
  select PROFILE in "${PROFILES[@]}"; do
    if [[ -n "$PROFILE" && " ${PROFILES[@]} " =~ " $PROFILE " ]]; then
      echo "✅ 你選擇了 profile: $PROFILE" >&2
      echo "$PROFILE"
      break
    else
      echo "請輸入有效選項" >&2
    fi
  done
}

# === Function: 取得 AWS region ===
get_aws_region() {
  local PROFILE=$1
  local DEFAULT_REGION
  local REGION
  
  DEFAULT_REGION=$(aws configure get region --profile "$PROFILE" 2>/dev/null | tr -d '\n\r' | xargs)
  
  if [ -z "$DEFAULT_REGION" ] || [ "$DEFAULT_REGION" = "None" ]; then
    echo "⚠️  選擇的 profile 沒有指定預設 region。" >&2
    read -p "請輸入 AWS region（例如 ap-northeast-1）: " REGION >&2
  else
    echo "📍 找到預設 region: $DEFAULT_REGION" >&2
    read -p "請輸入 AWS region（直接按 Enter 使用預設值 '$DEFAULT_REGION'）: " REGION >&2
    
    # 如果輸入為空，使用預設值
    if [ -z "$REGION" ]; then
      REGION="$DEFAULT_REGION"
    fi
  fi
  
  echo "✅ 使用 region: $REGION" >&2
  echo "$REGION"
}

# === Function: 建立 S3 bucket（如果不存在）===
create_s3_bucket_if_needed() {
  local PREFIX=$1
  local REGION=$2
  local PROFILE=$3
  local BUCKET_NAME="${PREFIX}-${REGION}-terraform-state"
  
  # 檢查 bucket 是否已存在
  if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
    echo "⚠️  S3 bucket '$BUCKET_NAME' 已存在。" >&2
  else
    echo "🚀 正在創建 S3 bucket: $BUCKET_NAME ..." >&2
    if [ "$REGION" == "us-east-1" ]; then
      aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --profile "$PROFILE"
    else
      aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION" \
        --profile "$PROFILE"
    fi
    
    # 啟用 versioning
    aws s3api put-bucket-versioning \
      --bucket "$BUCKET_NAME" \
      --versioning-configuration Status=Enabled \
      --profile "$PROFILE"
    
    echo "✅ S3 bucket 建立完成並已啟用版本控制: $BUCKET_NAME" >&2
  fi
  
  echo "$BUCKET_NAME"
}

# === Function: 取得 S3 bucket 前綴 ===
get_s3_prefix() {
  local PROFILE=$1
  local PREFIX
  
  echo "📍 使用 profile '$PROFILE' 作為預設前綴。" >&2
  read -p "請輸入 S3 Bucket 前綴（直接按 Enter 使用預設值 '$PROFILE'）: " PREFIX >&2
  
  # 如果輸入為空，使用 profile 名稱作為預設值
  if [ -z "$PREFIX" ]; then
    PREFIX="$PROFILE"
  fi
  
  echo "✅ 使用前綴: $PREFIX" >&2
  echo "$PREFIX"
}

# === Function: 詢問是否建立 EIP ===
ask_create_eip() {
  local TAG_NAME=$1
  local EXISTING_EIP
  
  # 先檢查是否已存在
  EXISTING_EIP=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=${TAG_NAME}" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'Addresses[0].AllocationId' \
    --output text 2>/dev/null)
  
  if [[ "$EXISTING_EIP" != "None" && -n "$EXISTING_EIP" ]]; then
    echo "✅ EIP '${TAG_NAME}' 已存在，AllocationId: $EXISTING_EIP" >&2
    return 0
  fi
  
  # 詢問是否要建立
  echo "❓ 是否要建立 EIP: ${TAG_NAME}？" >&2
  read -p "請輸入 y/yes 建立，其他按鍵跳過: " response >&2
  
  case "$response" in
    [yY]|[yY][eE][sS])
      create_eip_if_needed "$TAG_NAME"
      ;;
    *)
      echo "⏭️  跳過建立 EIP: ${TAG_NAME}" >&2
      ;;
  esac
}

# === Function: 檢查並建立 EIP（如果不存在）===
create_eip_if_needed() {
  local TAG_NAME=$1
  local EXISTING_EIP

  EXISTING_EIP=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=${TAG_NAME}" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'Addresses[0].AllocationId' \
    --output text 2>/dev/null)

  if [[ "$EXISTING_EIP" != "None" && -n "$EXISTING_EIP" ]]; then
    echo "✅ EIP '${TAG_NAME}' 已存在，AllocationId: $EXISTING_EIP"
  else
    echo "🚀 建立 EIP：${TAG_NAME}"
    NEW_ALLOCATION_ID=$(aws ec2 allocate-address \
      --domain vpc \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query 'AllocationId' \
      --output text)

    aws ec2 create-tags \
      --resources "$NEW_ALLOCATION_ID" \
      --tags "Key=Name,Value=${TAG_NAME}" \
      --region "$REGION" \
      --profile "$PROFILE"

    echo "✅ 已建立並標記 EIP '${TAG_NAME}'，AllocationId: $NEW_ALLOCATION_ID"
  fi
}

# === Step 1: 取得 AWS profile ===
PROFILE=$(get_aws_profile)

# === Step 2: 取得 AWS region ===
REGION=$(get_aws_region "$PROFILE")

# === Step 3: 取得 S3 前綴，並建立 bucket ===
PREFIX=$(get_s3_prefix "$PROFILE")
BUCKET_NAME=$(create_s3_bucket_if_needed "$PREFIX" "$REGION" "$PROFILE")

# === Step 4: 詢問並建立 EIP ===
echo "🔧 EIP 建立階段：" >&2
ask_create_eip "$PROFILE-nat-gateway"
ask_create_eip "$PROFILE-bastion"

echo "🎉 所有資源建立完成！可以開始 terraform 初始化囉。"
