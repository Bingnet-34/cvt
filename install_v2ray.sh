#!/bin/bash
# ================================================
# 🚀 V2Ray Auto Deploy Script for Google Cloud
# سكريبت إنشاء سيرفر V2Ray تلقائياً على Google Cloud
# ================================================

set -e

# ألوان للمخرجات
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║    🚀 V2Ray Auto Deploy - Custom Configuration       ║
║          إعدادات مخصصة - خادم V2Ray عالي الأداء      ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ================================================
# 🔧 الإعدادات المخصصة
# ================================================
V2RAY_PATH="khalildz_@cvw_cvw"
V2RAY_UUID="d2cb8181-233c-4d18-9972-8a1b04db0044"
V2RAY_PORT="8080"

TELEGRAM_BOT_TOKEN="8273677432:AAFwcfGj87HMq3w10HkHqdHBkpo_IkGWQcI"
TELEGRAM_CHAT_ID="8273677432"

# ================================================
# 📦 1. تثبيت المتطلبات الأساسية
# ================================================
echo -e "${YELLOW}[1] 📦 تثبيت المتطلبات الأساسية...${NC}"

sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    unzip \
    gnupg \
    apt-transport-https \
    ca-certificates

# ================================================
# ☁️ 2. تثبيت Google Cloud SDK
# ================================================
echo -e "${YELLOW}[2] ☁️ تثبيت Google Cloud SDK...${NC}"

if ! command -v gcloud &> /dev/null; then
    echo -e "${GREEN}📥 جاري تثبيت Google Cloud SDK...${NC}"
    
    # إضافة مستودع Google Cloud SDK
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
    
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    
    sudo apt-get update -y
    sudo apt-get install -y google-cloud-sdk
    
    echo -e "${GREEN}✅ تم تثبيت Google Cloud SDK${NC}"
else
    echo -e "${GREEN}✅ Google Cloud SDK مثبت مسبقاً${NC}"
fi

# ================================================
# 🔐 3. التحقق من تسجيل الدخول إلى Google Cloud
# ================================================
echo -e "${YELLOW}[3] 🔐 التحقق من تسجيل الدخول إلى Google Cloud...${NC}"

# التحقق إذا كان المستخدم مسجل دخول بالفعل
if gcloud auth list --format="value(account)" | grep -q "@"; then
    echo -e "${GREEN}✅ تم تسجيل الدخول بالفعل${NC}"
    CURRENT_USER=$(gcloud auth list --format="value(account)" | head -1)
    echo -e "${BLUE}👤 المستخدم الحالي: $CURRENT_USER${NC}"
else
    echo -e "${RED}❌ لم يتم تسجيل الدخول!${NC}"
    echo -e "${YELLOW}📢 يرجى تسجيل الدخول باستخدام الأمر التالي:${NC}"
    echo -e "${BLUE}gcloud auth login${NC}"
    exit 1
fi

# ================================================
# 📁 4. إنشاء مشروع جديد تلقائياً
# ================================================
echo -e "${YELLOW}[4] 📁 إنشاء مشروع جديد...${NC}"

# إنشاء معرف فريد للمشروع
PROJECT_ID="v2ray-server-$(date +%s | tail -c 6)"
PROJECT_NAME="V2Ray-High-Performance"

echo -e "${GREEN}🚀 إنشاء المشروع: $PROJECT_ID${NC}"
gcloud projects create $PROJECT_ID --name="$PROJECT_NAME" --quiet || {
    echo -e "${YELLOW}⚠️  قد يكون اسم المشروع مستخدماً، جاري استخدام مشروع عشوائي...${NC}"
    PROJECT_ID="v2ray-$(openssl rand -hex 4)"
    gcloud projects create $PROJECT_ID --name="V2Ray-Server-$(date +%H%M%S)" --quiet
}

# تعيين المشروع الحالي
gcloud config set project $PROJECT_ID --quiet
echo -e "${GREEN}✅ تم إنشاء وتعيين المشروع: $PROJECT_ID${NC}"

# ================================================
# ⚙️ 5. تفعيل APIs المطلوبة
# ================================================
echo -e "${YELLOW}[5] ⚙️ تفعيل خدمات Google Cloud...${NC}"

APIS=(
    "run.googleapis.com"
    "cloudbuild.googleapis.com"
    "containerregistry.googleapis.com"
    "compute.googleapis.com"
    "iam.googleapis.com"
)

for api in "${APIS[@]}"; do
    echo -e "${BLUE}🔧 تفعيل $api...${NC}"
    gcloud services enable $api --quiet
done

echo -e "${GREEN}✅ تم تفعيل جميع الخدمات${NC}"

# ================================================
# 🐳 6. إنشاء مجلد العمل والملفات
# ================================================
echo -e "${YELLOW}[6] 🐳 إنشاء مجلد العمل...${NC}"

WORKDIR="$HOME/v2ray-deploy-$(date +%s)"
mkdir -p $WORKDIR
cd $WORKDIR

echo -e "${GREEN}📁 مجلد العمل: $WORKDIR${NC}"

# ================================================
# 📄 7. إنشاء Dockerfile
# ================================================
echo -e "${YELLOW}[7] 📄 إنشاء Dockerfile...${NC}"

cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk add --no-cache \
    wget \
    unzip \
    openssl \
    ca-certificates \
    tzdata \
    bash

RUN mkdir -p /etc/v2ray /var/log/v2ray

RUN wget -q -O /tmp/v2ray.zip \
    https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip && \
    unzip -q /tmp/v2ray.zip -d /tmp/ && \
    mv /tmp/v2ray /usr/local/bin/ && \
    mv /tmp/v2ctl /usr/local/bin/ && \
    chmod +x /usr/local/bin/v2ray /usr/local/bin/v2ctl && \
    rm -rf /tmp/*

COPY config.json /etc/v2ray/config.json

RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/v2ray/privkey.pem \
    -out /etc/v2ray/fullchain.pem \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null

USER nobody
EXPOSE 8080

CMD ["/usr/local/bin/v2ray", "-config", "/etc/v2ray/config.json"]
EOF

echo -e "${GREEN}✅ تم إنشاء Dockerfile${NC}"

# ================================================
# ⚡ 8. إنشاء config.json
# ================================================
echo -e "${YELLOW}[8] ⚡ إنشاء config.json...${NC}"

cat > config.json << EOF
{
    "log": {
        "access": "/var/log/v2ray/access.log",
        "error": "/var/log/v2ray/error.log",
        "loglevel": "warning"
    },
    "inbounds": [{
        "port": 8080,
        "protocol": "vless",
        "settings": {
            "clients": [{
                "id": "$V2RAY_UUID",
                "level": 0,
                "email": "user@v2ray.com"
            }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "security": "tls",
            "tlsSettings": {
                "certificates": [{
                    "certificateFile": "/etc/v2ray/fullchain.pem",
                    "keyFile": "/etc/v2ray/privkey.pem"
                }]
            },
            "wsSettings": {
                "path": "/$V2RAY_PATH"
            }
        }
    }],
    "outbounds": [{
        "protocol": "freedom",
        "settings": {}
    }]
}
EOF

echo -e "${GREEN}✅ تم إنشاء config.json${NC}"

# ================================================
# 🚀 9. بناء ونشر السيرفر
# ================================================
echo -e "${YELLOW}[9] 🚀 بناء ونشر السيرفر...${NC}"

SERVICE_NAME="v2ray-hp-$(date +%s | tail -c 4)"
REGION="us-central1"

echo -e "${GREEN}🔨 جاري بناء الصورة...${NC}"
if ! gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME --quiet; then
    echo -e "${RED}❌ فشل في بناء الصورة${NC}"
    exit 1
fi

echo -e "${GREEN}☁️ جاري النشر على Cloud Run...${NC}"
if ! gcloud run deploy $SERVICE_NAME \
  --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --port=8080 \
  --memory=16Gi \
  --cpu=8 \
  --max-instances=100 \
  --min-instances=0 \
  --concurrency=1000 \
  --timeout=100s \
  --execution-environment=gen2 \
  --quiet \
  --format=json > deployment.json 2>&1; then
    
    echo -e "${RED}❌ فشل في نشر السيرفر${NC}"
    echo -e "${YELLOW}📋 محاولة النشر بإعدادات مخفضة...${NC}"
    
    # محاولة بإعدادات أقل
    gcloud run deploy $SERVICE_NAME \
      --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
      --platform=managed \
      --region=$REGION \
      --allow-unauthenticated \
      --port=8080 \
      --memory=4Gi \
      --cpu=2 \
      --max-instances=10 \
      --min-instances=0 \
      --concurrency=80 \
      --timeout=300s \
      --quiet \
      --format=json > deployment.json
fi

SERVICE_URL=$(jq -r '.status.url' deployment.json 2>/dev/null || echo "")
if [ -z "$SERVICE_URL" ] || [ "$SERVICE_URL" = "null" ]; then
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format='value(status.url)' 2>/dev/null || echo "")
fi

if [ -z "$SERVICE_URL" ]; then
    echo -e "${RED}❌ فشل في الحصول على رابط السيرفر${NC}"
    exit 1
fi

DOMAIN=$(echo $SERVICE_URL | sed 's|https://||' | sed 's|/.*||')

echo -e "${GREEN}✅ تم النشر بنجاح!${NC}"
echo -e "${GREEN}🔗 رابط السيرفر: $SERVICE_URL${NC}"

# ================================================
# 🔗 10. إنشاء روابط V2Ray
# ================================================
echo -e "${YELLOW}[10] 🔗 إنشاء روابط V2Ray...${NC}"

VLESS_URL="vless://$V2RAY_UUID@$DOMAIN:443?type=ws&security=tls&path=%2F$V2RAY_PATH&host=$DOMAIN&sni=$DOMAIN&fp=chrome#V2Ray-HP-Server"

echo -e "${GREEN}✅ تم إنشاء رابط VLESS${NC}"

# ================================================
# 📊 11. إنشاء روابط لوحة التحكم
# ================================================
echo -e "${YELLOW}[11] 📊 إنشاء روابط لوحة التحكم...${NC}"

DASHBOARD_URL="https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/metrics?project=$PROJECT_ID"
LOGS_URL="https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/logs?project=$PROJECT_ID"

# ================================================
# 🤖 12. إرسال المعلومات إلى تليجرام
# ================================================
echo -e "${YELLOW}[12] 🤖 إرسال المعلومات إلى تليجرام...${NC}"

TELEGRAM_MESSAGE="🚀 *تم إنشاء سيرفر V2Ray بنجاح!*

📁 *المشروع:* \`$PROJECT_ID\`
🏷️ *اسم السيرفر:* \`$SERVICE_NAME\`
🌍 *المنطقة:* \`$REGION\`

⚡ *مواصفات السيرفر:*
├─ 💾 *الذاكرة:* 16Gi
├─ 🎯 *المعالج:* 8 CPUs
├─ ⏱️ *مهلة الطلب:* 100s
├─ 🔄 *الطلبات المتزامنة:* 1000
├─ 🚀 *بيئة التنفيذ:* الجيل الثاني
└─ 🌐 *الوصول العام:* ✅ مفعل

🔗 *رابط السيرفر:*
\`$SERVICE_URL\`

🔑 *معلومات الاتصال:*
├─ *UUID:* \`$V2RAY_UUID\`
├─ *المسار:* \`/$V2RAY_PATH\`
└─ *المنفذ:* \`443\`

📊 *لوحة التحكم:*
├─ 📈 [عرض المقاييس]($DASHBOARD_URL)
├─ 📝 [عرض السجلات]($LOGS_URL)

🌐 *رابط VLESS:*
\`$VLESS_URL\`

⏰ *وقت الإنشاء:* $(date '+%Y-%m-%d %H:%M:%S')

📌 *حفظ هذه المعلومات في مكان آمن.*"

# محاولة إرسال الرسالة
if ! curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d "chat_id=$TELEGRAM_CHAT_ID" \
  -d "text=$TELEGRAM_MESSAGE" \
  -d "parse_mode=Markdown" \
  -d "disable_web_page_preview=true" > /dev/null; then
    echo -e "${YELLOW}⚠️  تعذر إرسال الرسالة إلى التليجرام${NC}"
else
    echo -e "${GREEN}✅ تم إرسال الرسالة إلى التليجرام${NC}"
fi

# إرسال رابط VLESS منفصل
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d "chat_id=$TELEGRAM_CHAT_ID" \
  -d "text=🔗 *رابط VLESS الكامل:*\n\`$VLESS_URL\`" \
  -d "parse_mode=Markdown" > /dev/null || true

# ================================================
# 📱 13. إنشاء وإرسال QR Code
# ================================================
echo -e "${YELLOW}[13] 📱 إنشاء QR Code...${NC}"

# تثبيت متطلبات QR Code
pip3 install qrcode[pil] pillow --quiet 2>/dev/null || {
    echo -e "${YELLOW}⚠️  تثبيت متطلبات QR Code...${NC}"
    python3 -m pip install qrcode[pil] pillow --quiet
}

cat > generate_qr.py << 'EOF'
import qrcode
import sys
import os

data = sys.argv[1] if len(sys.argv) > 1 else ""
if data:
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save("vless_qr.png")
    print("QR Code generated")
EOF

python3 generate_qr.py "$VLESS_URL"

if [ -f "vless_qr.png" ]; then
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendPhoto" \
      -F "chat_id=$TELEGRAM_CHAT_ID" \
      -F "photo=@vless_qr.png" \
      -F "caption=📱 QR Code للاتصال السريع" > /dev/null || echo -e "${YELLOW}⚠️  تعذر إرسال QR Code${NC}"
else
    echo -e "${YELLOW}⚠️  تعذر إنشاء QR Code${NC}"
fi

# ================================================
# 📄 14. إنشاء ملف الإعدادات
# ================================================
echo -e "${YELLOW}[14] 📄 إنشاء ملف الإعدادات...${NC}"

cat > v2ray_config.txt << EOF
==========================================
🚀 إعدادات سيرفر V2Ray - Google Cloud Run
==========================================

📋 المعلومات الأساسية:
• المشروع: $PROJECT_ID
• اسم السيرفر: $SERVICE_NAME
• المنطقة: $REGION
• رابط السيرفر: $SERVICE_URL
• النطاق: $DOMAIN

⚡ مواصفات السيرفر:
• الذاكرة: 16Gi
• المعالج: 8 CPUs
• مهلة الطلب: 100s
• الطلبات المتزامنة: 1000
• بيئة التنفيذ: الجيل الثاني
• الوصول العام: مفعل
• الحد الأقصى للنسخ: 100
• الحد الأدنى للنسخ: 0

🔑 إعدادات V2Ray:
• UUID: $V2RAY_UUID
• المسار: /$V2RAY_PATH
• المنفذ: 443
• البروتوكول: VLESS
• النقل: WebSocket (WS)
• الأمان: TLS

🌐 روابط التحكم:
• لوحة المقاييس: $DASHBOARD_URL
• سجلات النظام: $LOGS_URL

🔗 رابط VLESS الكامل:
$VLESS_URL

📱 إعدادات التطبيقات:

1. V2RayN:
{
  "address": "$DOMAIN",
  "port": 443,
  "id": "$V2RAY_UUID",
  "alterId": 0,
  "security": "auto",
  "network": "ws",
  "path": "/$V2RAY_PATH",
  "host": "$DOMAIN",
  "tls": "tls",
  "sni": "$DOMAIN"
}

2. NekoBox:
vless://$(echo -n '{
  "v": "2",
  "ps": "Google Cloud V2Ray",
  "add": "'$DOMAIN'",
  "port": "443",
  "id": "'$V2RAY_UUID'",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "'$DOMAIN'",
  "path": "/'$V2RAY_PATH'",
  "tls": "tls",
  "sni": "'$DOMAIN'",
  "fp": "chrome"
}' | base64 | tr -d '\n')

⏰ وقت الإنشاء: $(date '+%Y-%m-%d %H:%M:%S')
==========================================
EOF

# إرسال ملف الإعدادات
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
  -F "chat_id=$TELEGRAM_CHAT_ID" \
  -F "document=@v2ray_config.txt" \
  -F "caption=📄 ملف الإعدادات الكامل" > /dev/null || echo -e "${YELLOW}⚠️  تعذر إرسال ملف الإعدادات${NC}"

# ================================================
# 🎯 15. اختبار الاتصال
# ================================================
echo -e "${YELLOW}[15] 🎯 اختبار الاتصال...${NC}"

echo -e "${BLUE}🔍 جاري اختبار الاتصال بالسيرفر...${NC}"
if timeout 15 curl -s -I "$SERVICE_URL" > /dev/null; then
    echo -e "${GREEN}✅ السيرفر يعمل بنجاح!${NC}"
else
    echo -e "${YELLOW}⚠️  قد يستغرق السيرفر 1-2 دقائق للبدء${NC}"
    echo -e "${BLUE}📢 يمكنك اختباره يدوياً لاحقاً:${NC}"
    echo -e "${BLUE}curl -I $SERVICE_URL${NC}"
fi

# ================================================
# 📝 16. إنشاء سكريبت الإدارة
# ================================================
echo -e "${YELLOW}[16] 📝 إنشاء سكريبت الإدارة...${NC}"

cat > manage_v2ray.sh << EOF
#!/bin/bash
# سكريبت إدارة سيرفر V2Ray

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

case "\$1" in
    status)
        echo -e "\${BLUE}📊 حالة السيرفر:\${NC}"
        gcloud run services describe $SERVICE_NAME \\
          --platform=managed \\
          --region=$REGION \\
          --format="value(status.conditions[0].type, status.conditions[0].status)"
        ;;
    logs)
        echo -e "\${BLUE}📝 سجلات السيرفر:\${NC}"
        gcloud run logs tail $SERVICE_NAME --region=$REGION --limit=20
        ;;
    info)
        echo -e "\${GREEN}📋 معلومات السيرفر:\${NC}"
        echo "المشروع: $PROJECT_ID"
        echo "الاسم: $SERVICE_NAME"
        echo "المنطقة: $REGION"
        echo "الرابط: $SERVICE_URL"
        echo "النطاق: $DOMAIN"
        echo "UUID: $V2RAY_UUID"
        echo "المسار: /$V2RAY_PATH"
        echo "لوحة التحكم: $DASHBOARD_URL"
        ;;
    delete)
        echo -e "\${RED}⚠️  هل تريد حذف السيرفر؟ (y/n): \${NC}"
        read -n 1 confirm
        echo
        if [ "\$confirm" = "y" ] || [ "\$confirm" = "Y" ]; then
            gcloud run services delete $SERVICE_NAME \\
              --platform=managed \\
              --region=$REGION \\
              --quiet
            echo -e "\${GREEN}✅ تم حذف السيرفر\${NC}"
        else
            echo -e "\${YELLOW}❌ تم الإلغاء\${NC}"
        fi
        ;;
    *)
        echo -e "\${BLUE}استخدام: manage_v2ray.sh [command]\${NC}"
        echo -e "\${GREEN}الأوامر:\${NC}"
        echo "  status   - عرض حالة السيرفر"
        echo "  logs     - عرض السجلات"
        echo "  info     - عرض المعلومات"
        echo "  delete   - حذف السيرفر"
        ;;
esac
EOF

chmod +x manage_v2ray.sh
mv manage_v2ray.sh ~/

echo -e "${GREEN}✅ تم إنشاء سكريبت الإدارة في: ~/manage_v2ray.sh${NC}"

# ================================================
# 🎉 17. عرض النتائج النهائية
# ================================================
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                    🎉 تم الانتهاء!                    ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}📋 ملخص المعلومات:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "🏷️  ${YELLOW}اسم السيرفر:${NC} $SERVICE_NAME"
echo -e "🌍 ${YELLOW}المنطقة:${NC} $REGION"
echo -e "🔗 ${YELLOW}الرابط:${NC} $SERVICE_URL"
echo -e "📊 ${YELLOW}لوحة التحكم:${NC} $DASHBOARD_URL"
echo -e "🔑 ${YELLOW}UUID:${NC} $V2RAY_UUID"
echo -e "🛣️  ${YELLOW}المسار:${NC} /$V2RAY_PATH"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${GREEN}🚀 أوامر الإدارة:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "📊 ${YELLOW}عرض الحالة:${NC} ~/manage_v2ray.sh status"
echo -e "📝 ${YELLOW}عرض السجلات:${NC} ~/manage_v2ray.sh logs"
echo -e "🗑️  ${YELLOW}حذف السيرفر:${NC} ~/manage_v2ray.sh delete"
echo -e "📋 ${YELLOW}المعلومات:${NC} ~/manage_v2ray.sh info"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${GREEN}✅ تم إرسال جميع المعلومات إلى بوت تليجرام${NC}"
echo -e "${BLUE}========================================${NC}"

# تنظيف الملفات المؤقتة
rm -f deployment.json generate_qr.py vless_qr.png v2ray_config.txt 2>/dev/null || true

# حفظ المعلومات في ملف
cat > ~/v2ray_server_info.txt << EOF
معلومات سيرفر V2Ray:
المشروع: $PROJECT_ID
اسم السيرفر: $SERVICE_NAME
المنطقة: $REGION
الرابط: $SERVICE_URL
النطاق: $DOMAIN
UUID: $V2RAY_UUID
المسار: /$V2RAY_PATH
لوحة التحكم: $DASHBOARD_URL
وقت الإنشاء: $(date)
EOF

echo -e "${GREEN}📄 تم حفظ المعلومات في: ~/v2ray_server_info.txt${NC}"
