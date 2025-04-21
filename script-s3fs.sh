#!/bin/bash

declare -a MOUNTED_POINTS;
ALL_MATCH=true;
CUSTOMER_NAME="XPTO";
INSTANCE_NAME=$(hostname);
AWS_REGION="us-east-1";
PARAMETER_NAME_BOT_TOKEN="TOKEN_BOT_API_TELEGRAM";
PARAMETER_NAME_CHAT_ID="CHAT_ID_TELEGRAM";
PARAMETER_NAME_MAIL_FROM="MAIL_FROM_NOTIFICATION_S3FS";
PARAMETER_NAME_MAIL_TO="MAIL_TO_NOTIFICATION_S3FS";

BOT_TOKEN=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_BOT_TOKEN" --with-decryption --query "Parameter.Value" --output text);
CHAT_ID=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_CHAT_ID" --with-decryption --query "Parameter.Value" --output text);
MAIL_FROM=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_MAIL_FROM" --with-decryption --query "Parameter.Value" --output text);
MAIL_TO=$(aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_NAME_MAIL_TO" --with-decryption --query "Parameter.Value" --output text);

send_notification_telegram(){
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$FULL_MESSAGE" \
        -d parse_mode="HTML" > /dev/null;
}

send_notification_email(){
  echo -e "To: $MAIL_TO\nSubject: $TITULO\n\n$FULL_MESSAGE" | /usr/sbin/sendmail -t -f "$MAIL_FROM" "$MAIL_TO";
}

compare_before_after_mounted_points(){
  while IFS= read -r POINT; do
      UPDATE_MOUNTED_POINTS+=("$POINT")
  done < <(df -hT | sort | awk '$2 == "fuse.s3fs" {print $NF}')

  if [ "${#MOUNTED_POINTS[@]}" -ne "${#UPDATE_MOUNTED_POINTS[@]}" ]; then
      ALL_MATCH=false;
  else
      for i in "${!MOUNTED_POINTS[@]}"; do
          if [ "${MOUNTED_POINTS[$i]}" != "${UPDATE_MOUNTED_POINTS[$i]}" ]; then
              ALL_MATCH=false;
              break;
          fi
      done
  fi
}

list_s3fs_disks_after_remount() {
  local RESULT=""
  declare -a BUCKETS
  declare -a MOUNT_POINTS

  while read -r line; do
    # Extrai o nome do bucket e o ponto de montagem a partir do fstab
    BUCKET=$(echo "$line" | cut -d '#' -f2 | awk '{print $1}')
    MOUNT_POINT=$(echo "$line" | awk '{print $2}')

    # Verifica se o ponto de montagem está montado com fuse.s3fs
    if findmnt -rn -t fuse.s3fs -T "$MOUNT_POINT" > /dev/null; then
      BUCKETS+=("$BUCKET")
      MOUNT_POINTS+=("$MOUNT_POINT")
    fi
  done < <(grep 's3fs#' /etc/fstab)

  # Monta a saída formatada
  for i in "${!BUCKETS[@]}"; do
    RESULT+=$'\n'"🪣  <b>Bucket:</b> ${BUCKETS[$i]} → <b>Montado em:</b> ${MOUNT_POINTS[$i]}"$'\n';
  done

  echo "$RESULT";
}


discovery_s3fs_no_mounted_disks(){
  while IFS= read -r POINT; do
    MOUNTED_POINTS+=("$POINT");
  done < <(df -hT | sort | awk '$2 == "fuse.s3fs" {print $NF}');

  if [ ${#MOUNTED_POINTS[@]} -eq 0 ]; then
    local TITULO="<b>🚨  [$CUSTOMER_NAME] CRITICAL: RESTARTANDO DISCOS S3FS:</b>";
    local INSTANCE_INFO="<b>Nome da Instância:</b> $INSTANCE_NAME";
    local INF1="<b>Verificando os discos s3fs atualmente montados:</b>  ⏳ ⏳ ⏳";
    local INF2="<b>Não há discos S3FS montados:</b> ❌ ❌ ❌";
    FULL_MESSAGE="$TITULO"$'\n'"$INSTANCE_INFO"$'\n'"$INF1"$'\n'"$INF2";
    send_notification_telegram;
    send_notification_email;
    exit 0;
  fi
}

restart_s3fs_disks() {
    local TITULO="<b>ℹ️  [$CUSTOMER_NAME] INF: RESTARTANDO DISCOS S3FS:</b>";
    local INSTANCE_INFO="<b>Nome da Instância:</b> $INSTANCE_NAME";
    local INF1="<b>Discos s3fs atualmente montados:</b>";
    local INF2="<b>Desmontando os discos s3fs:</b> ⏳ ⏳ ⏳";
    FULL_MESSAGE="$TITULO"$'\n'"$INSTANCE_INFO"$'\n'"$INF1"$'\n';

    for S3FS_DISKS in "${MOUNTED_POINTS[@]}"; do
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$S3FS_DISKS ✅";
    done

    FULL_MESSAGE="$FULL_MESSAGE"$'\n'$'\n'"$INF2";

    for S3FS_DISKS_LIST in "${MOUNTED_POINTS[@]}"; do
       fusermount -uz "$S3FS_DISKS_LIST";
    done

    VERIFY_DISKS_RESULT=$(df -hT | sort | awk '$2 == "fuse.s3fs" {print $NF}');

    if [ -z "$VERIFY_DISKS_RESULT" ]; then
      local INF3="<b>✅ SUCCESS:</b> Discos desmontados com sucesso!";
      FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF3"$'\n'"#############################################";
      local INF4="<b>Remontando os discos S3FS:</b> 🛠️ 🛠️ 🛠️";
      FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF4";
      mount -a;
      STATUS_CODE_MOUNT_COMMAND=$(/usr/bin/echo $?);
      compare_before_after_mounted_points;
       
      if [ "$STATUS_CODE_MOUNT_COMMAND" -eq 0 ] && [ $ALL_MATCH == "true" ]; 
      then
         local INF5="<b>✅ Discos remontados com sucesso!!!</b>";
         FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF5"
         MOUNTED_RESULT=$(list_s3fs_disks_after_remount);
         FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$MOUNTED_RESULT";
         send_notification_telegram;
         send_notification_email;
      else
         local INF6="<b>🚨 ERROR:</b> Por favor verificar pessoalmente!!! ❌ ❌ ❌";
         FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF6";
	 MOUNTED_RESULT=$(list_s3fs_disks_after_remount);
         FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$MOUNTED_RESULT";
         send_notification_telegram;
         send_notification_email;
      fi
    fi
}

discovery_s3fs_no_mounted_disks;
restart_s3fs_disks;

