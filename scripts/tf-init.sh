#!/bin/bash

# 用來在 foo-infra 之前建立需要的資源

set -e  # 出錯即停止
set -u  # 使用未定義變數時報錯

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

# === Step 1: 取得 AWS profile 列表 ===
AWS_CONFIG_FILE="$HOME/.aws/credentials"

echo "🔍 可用的 AWS profiles："
PROFILES=($(grep '^\[' "$AWS_CONFIG_FILE" | sed 's/^\[\(.*\)\]$/\1/' | grep -v '^default$'))

if [ ${#PROFILES[@]} -eq 0 ]; then
  echo "❌ 沒有發現非 default 的 AWS profiles，請先設定 ~/.aws/credentials"
  exit 1
fi

echo
select PROFILE in "${PROFILES[@]}"; do
  if [[ -n "$PROFILE" && " ${PROFILES[@]} " =~ " $PROFILE " ]]; then
    echo "✅ 你選擇了 profile: $PROFILE"
    break
  else
    echo "請輸入有效選項"
  fi
done

# === Step 2: 取得 region（從 profile 或手動輸入）===
REGION=$(aws configure get region --profile "$PROFILE")

if [ -z "$REGION" ]; then
  echo "⚠️  選擇的 profile 沒有指定 region，請手動輸入。"
  read -p "請輸入 AWS region（例如 ap-northeast-1）: " REGION
fi

# === Step 3: 輸入 S3 前綴，並組出 bucket 名稱 ===
read -p "請輸入 S3 Bucket 前綴 (例如：xa-uat)： " PREFIX
BUCKET_NAME="${PREFIX}-${REGION}-terraform-state"

# === Step 4: 檢查 bucket 是否已存在 ===
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
  echo "⚠️  S3 bucket '$BUCKET_NAME' 已存在。"
else
  echo "🚀 正在創建 S3 bucket: $BUCKET_NAME ..."
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

  echo "✅ S3 bucket 建立完成並已啟用版本控制: $BUCKET_NAME"
fi

BUCKET_NAME="${PREFIX}-${REGION}-alb-logs"

# === Step 4: 檢查 bucket 是否已存在 ===
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
  echo "⚠️  S3 bucket '$BUCKET_NAME' 已存在。"
else
  echo "🚀 正在創建 S3 bucket: $BUCKET_NAME ..."
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

  echo "✅ S3 bucket 建立完成: $BUCKET_NAME"
fi

# # === Step 5: 建立並標記兩個 EIP ===
create_eip_if_needed "nat-gateway"
create_eip_if_needed "bastion"

echo "🎉 所有資源建立完成！可以開始 terraform 初始化囉。"
