#!/bin/bash

declare -a MOUNTED_POINTS;
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
  echo -e "To: $MAIL_TO\nSubject: $TITULO\n\n$FULL_MESSAGE" | /usr/sbin/sendmail -t -f $MAIL_FROM $MAIL_TO;
}

discovery_s3fs_no_mounted_disks(){
  while IFS= read -r POINT; do
    MOUNTED_POINTS+=("$POINT");
  done < <(df -hT | awk '$2 == "fuse.s3fs" {print $NF}');
  if [ ${#MOUNTED_POINTS[@]} -eq 0 ];
  then
    local TITULO="<b>🚨 [$CUSTOMER_NAME] CRITICAL: RESTARTANDO DISCOS S3FS:</b>";
    local INSTANCE_NAME="<b>Nome da Instância:</b> $INSTANCE_NAME";
    local INF1="<b>Verificando os discos s3fs atualmente montados:</b>  ⏳⏳⏳  ";
    local INF2="<b>Não há discos S3FS montados:</b> ❌❌❌";
    local FULL_MESSAGE="$TITULO"$'\n'"$INSTANCE_NAME"$'\n'"$INF1"$'\n'"$INF2";
    send_notification_telegram;
    send_notification_email;
    exit 0;
  fi
}

restart_s3fs_disks() {
    local TITULO="<b>ℹ️  [$CUSTOMER_NAME] INF: RESTARTANDO DISCOS S3FS:</b>";
    local INSTANCE_NAME="<b>Nome da Instância:</b> $INSTANCE_NAME";
    local INF1="<b>Discos s3fs atualmente montados:</b>";
    local INF2="<b>Desmontando os discos s3fs:</b> ⏳⏳⏳";
    local FULL_MESSAGE="$TITULO"$'\n'"$INSTANCE_NAME"$'\n'"$INF1";

    for S3FS_DISKS in "${MOUNTED_POINTS[@]}"; do
        FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$S3FS_DISKS  ✅";
    done

    FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF2";

    for S3FS_DISKS_LIST in "${MOUNTED_POINTS[@]}"; do
       fusermount -uz "$S3FS_DISKS_LIST";
    done

    VERIFY_DISKS_RESULT=$(df -hT | awk '$2 == "fuse.s3fs" {print $NF}');

    if [ -z $VERIFY_DISKS_RESULT ];
    then
      local INF3="<b>✅ SUCCESS:</b> Discos desmontados com sucesso!!!";
      FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF3"$'\n'"##########################################";
      local INF4="<b>Remontando os discos S3FS:</b> 🛠️🛠️🛠️";
      FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF4";
      mount -a;
      if [ $? -eq 0 ];
      then
	 local INF5="<b>✅ Discos remontados com sucesso!!!</b>";
	 FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF5";
	 send_notification_telegram;
	 send_notification_email;
      else
         local INF6="<b>🚨FAILED: Falha ao montar discos!!! - Por favor verifique pessoalmente!!!</b> ❌ ❌ ❌";
         FULL_MESSAGE="$FULL_MESSAGE"$'\n'"$INF6";
	 send_notification_telegram;
	 send_notification_email;
      fi
    fi
}

discovery_s3fs_no_mounted_disks;
restart_s3fs_disks;

