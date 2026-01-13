


#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
بوت تليجرام لإنشاء ملفات تكوين V2Ray (متوافق مع Pydroid 3)
ملاحظات:
- في بيئة Pydroid3 عادة لا يتوفر docker أو gcloud.
- السكريبت يقوم بإنشاء Dockerfile و config.json ويقوم بضغطهما وإرسالهما كمستند ZIP.
- إن كان gcloud مثبتاً في PATH، سيحاول السكريبت استخدامه لنشر الصورة تلقائياً.
"""

import os
import sys
import json
import uuid
import time
import base64
import tempfile
import threading
import re
import logging
import zipfile
import shutil
from datetime import datetime
from pathlib import Path
from io import BytesIO

try:
    import telebot
    from telebot import types
except Exception as e:
    print("❌ تأكد من تثبيت pyTelegramBotAPI: pip install pyTelegramBotAPI")
    raise

try:
    import qrcode
except Exception as e:
    print("❌ تأكد من تثبيت qrcode و pillow: pip install qrcode pillow")
    raise

# إعداد logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# تحميل متغير البيئة أو طباعة طلب إدخال (مفيد في Pydroid)
BOT_TOKEN = os.getenv('8273677432:AAFwcfGj87HMq3w10HkHqdHBkpo_IkGWQcI')
if not BOT_TOKEN:
    logger.info("🔧 لم يتم العثور على BOT_TOKEN في المتغيرات البيئية.")
    BOT_TOKEN = input("🔑 أدخل توكن البوت: ").strip()
    if not BOT_TOKEN:
        sys.exit("❌ يجب إدخال توكن البوت!")

bot = telebot.TeleBot(BOT_TOKEN)

# إعداد V2Ray الافتراضي (يمكنك تخصيصه لاحقًا)
V2RAY_CONFIG = {
    "path": "khalildz_@cvw_cvw",
    "uuid": "d2cb8181-233c-4d18-9972-8a1b04db0044",
    "port": 8080
}

# مواصفات افتراضية للخادم (معلومات عرض فقط)
SERVER_SPECS = {
    "memory": "16Gi",
    "cpu": "8000m",
    "timeout": "100s",
    "concurrency": 1000,
    "max_instances": 100,
    "min_instances": 0,
    "platform": "managed",
    "region": "us-central1",
    "allow_unauthenticated": True,
    "execution_environment": "gen2"
}

user_sessions = {}

class CloudRunDeployer:
    """منشئ ملفات للنشر وطرق مساعدة (مناسب لـ Pydroid: لا يبني صور محلياً)"""

    def __init__(self):
        self.region = SERVER_SPECS['region']

    def extract_credentials_from_url(self, skills_url: str):
        """استخراج project, email, token من رابط Google Skills"""
        try:
            logger.info(f"🔍 تحليل الرابط: {skills_url[:60]}...")
            project_id = None
            token = None
            email = None

            # استخراج token (إن وُجد)
            token_match = re.search(r'token=([^&]+)', skills_url)
            if token_match:
                token = token_match.group(1)

            # استخراج project عبر استراتيجيات متعددة
            project_match = re.search(r'project[=%3D]([^&]+)', skills_url)
            if project_match:
                project_id = project_match.group(1)
                project_id = unquote_safe(project_id)

            # استخراج email إن وُجد
            email_match = re.search(r'[Ee]mail%3D([^%&]+)', skills_url)
            if email_match:
                email = unquote_safe(email_match.group(1))
            else:
                em2 = re.search(r'email=([^&]+)', skills_url)
                if em2:
                    email = unquote_safe(em2.group(1))

            if not project_id:
                project_id = f"qwiklabs-{uuid.uuid4().hex[:16]}"
                logger.warning(f"⚠️ لم يُعثر على project_id في الرابط. تم إنشاء: {project_id}")

            if not email:
                email = f"student-{uuid.uuid4().hex[:8]}@qwiklabs.net"

            creds = {
                'project_id': project_id,
                'email': email,
                'token': token if token else "NO_TOKEN_FOUND",
                'original_url': skills_url
            }
            logger.info(f"✅ استخراج: project={project_id}, email={email}")
            return creds
        except Exception as e:
            logger.error(f"❌ خطأ في extract_credentials_from_url: {e}")
            return None

    def create_docker_image_files(self, server_name: str):
        """
        ينشئ مجلداً مؤقتاً يحوي:
        - Dockerfile جاهز لاستخدام صورة v2ray أو لتضمين التنفيذ
        - config.json الخاص بـ V2Ray
        - README.txt بإرشادات بناء/نشر
        لا يحاول بناء الصورة محلياً (لأن Docker عادة غير متاح في Pydroid).
        """
        try:
            temp_dir = tempfile.mkdtemp(prefix=f"v2ray_{server_name}_")
            logger.info(f"📁 مجلد مؤقت: {temp_dir}")

            dockerfile_content = f'''FROM alpine:latest

# متطلبات أساسية
RUN apk add --no-cache curl wget unzip openssl ca-certificates tzdata && \\
    mkdir -p /etc/v2ray /var/log/v2ray

# تحميل نسخة v2ray (قد تحتاج لتحديث الرابط لاحقاً)
RUN wget -q -O /tmp/v2ray.zip https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip && \\
    unzip -q /tmp/v2ray.zip -d /tmp/ && \\
    mv /tmp/v2ray /usr/local/bin/ && \\
    mv /tmp/v2ctl /usr/local/bin/ && \\
    chmod +x /usr/local/bin/v2ray /usr/local/bin/v2ctl && \\
    rm -rf /tmp/*

COPY config.json /etc/v2ray/config.json

# شهادة بسيطة (للاختبار فقط)
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\
    -keyout /etc/v2ray/privkey.pem \\
    -out /etc/v2ray/fullchain.pem \\
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null

USER nobody
EXPOSE 443

CMD ["/usr/local/bin/v2ray", "-config", "/etc/v2ray/config.json"]
'''

            v2ray_conf = {
                "log": {
                    "access": "/var/log/v2ray/access.log",
                    "error": "/var/log/v2ray/error.log",
                    "loglevel": "warning"
                },
                "inbounds": [{
                    "port": 443,
                    "protocol": "vless",
                    "settings": {
                        "clients": [{
                            "id": V2RAY_CONFIG['uuid'],
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
                            "path": f"/{V2RAY_CONFIG['path']}",
                            "headers": {"Host": ""}
                        }
                    }
                }],
                "outbounds": [{"protocol": "freedom", "settings": {}}]
            }

            with open(os.path.join(temp_dir, "Dockerfile"), "w") as f:
                f.write(dockerfile_content)

            with open(os.path.join(temp_dir, "config.json"), "w") as f:
                json.dump(v2ray_conf, f, indent=2)

            readme = (
                "ملفات تم إنشاؤها بواسطة بوت V2Ray (Pydroid).\n\n"
                "لتشغيل على جهاز يحتوي على Docker/GCloud:\n"
                "1) انسخ المجلد إلى جهاز يدعم Docker.\n"
                "2) من داخل المجلد شغّل:\n"
                "   docker build -t v2ray-custom:latest .\n"
                "3) ثم ادفع الصورة إلى GCR/Github Container Registry إن أردت النشر على Cloud Run.\n\n"
                "أو يمكنك رفع المجلد مباشرة إلى منصة تدعم بنية حاويات لبناء الصورة."
            )
            with open(os.path.join(temp_dir, "README.txt"), "w") as f:
                f.write(readme)

            logger.info("✅ تم إنشاء Dockerfile و config.json و README")
            return temp_dir

        except Exception as e:
            logger.error(f"❌ خطأ في create_docker_image_files: {e}")
            return None

    def deploy_to_cloud_run_if_possible(self, project_id: str, server_name: str, temp_dir: str):
        """
        يحاول نشر الصورة عبر gcloud إن كانت مثبتة على الجهاز.
        في Pydroid أرجّح أنها غير مثبتة، فيُعاد None ليتم إرسال ZIP للمستخدم.
        """
        try:
            from shutil import which
            if not which("gcloud"):
                logger.info("ℹ️ gcloud غير مثبت أو غير في PATH. سيتم إرجاع None لإرسال الأرشيف.")
                return None

            # محاولة بناء ورفع (إن وُجد gcloud) - ملاحظة: على أندرويد قد يفشل
            image_tag = f"gcr.io/{project_id}/{server_name}:latest"
            build_cmd = f"gcloud builds submit {temp_dir} --tag={image_tag} --project={project_id} --quiet"
            deploy_cmd = f"gcloud run deploy {server_name} --image={image_tag} --platform=managed --region={self.region} --allow-unauthenticated --project={project_id} --quiet"

            logger.info("🔨 محاولة تشغيل أوامر gcloud (هذا سينجح فقط إن كان gcloud مثبتاً).")
            res1 = os.system(build_cmd)
            if res1 != 0:
                logger.warning("⚠️ فشل gcloud builds submit أو قيمة non-zero. سيتم الإرجاع لمجرّد إرسال الأرشيف.")
                return None

            res2 = os.system(deploy_cmd)
            if res2 != 0:
                logger.warning("⚠️ فشل gcloud run deploy. سيتم الإرجاع لمجرّد إرسال الأرشيف.")
                return None

            # حاول الحصول على URL
            describe_cmd = f"gcloud run services describe {server_name} --platform=managed --region={self.region} --project={project_id} --format=json"
            stream = os.popen(describe_cmd)
            out = stream.read()
            try:
                info = json.loads(out)
                url = info.get("status", {}).get("url")
                return url
            except:
                return None
        except Exception as e:
            logger.warning(f"⚠️ استثناء أثناء попытка النشر: {e}")
            return None

def unquote_safe(s: str):
    try:
        from urllib.parse import unquote
        return unquote(s)
    except:
        return s

# Handlers بوت
@bot.message_handler(commands=['start', 'help'])
def send_welcome(message):
    chat_id = message.chat.id
    username = message.from_user.username or "المستخدم"
    welcome_text = f"""
🚀 مرحباً @{username} — بوت إنشاء ملفات V2Ray (نسخة Pydroid)

كيفية الاستخدام:
1) أرسل رابط Google Skills (مثال يحتوي على project=)
2) أكد المواصفات
3) ستحصل على ملفات Docker + config.json مضغوطة لو لم يتوفر gcloud على جهازك.
"""
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    markup.add(types.KeyboardButton('🔄 تحديث الحالة'), types.KeyboardButton('ℹ️ التعليمات'))
    bot.send_message(chat_id, welcome_text, reply_markup=markup)

@bot.message_handler(commands=['status'])
def check_status(message):
    chat_id = message.chat.id
    if chat_id in user_sessions:
        s = user_sessions[chat_id]
        status = s.get('status', 'unknown')
        project = s.get('credentials', {}).get('project_id', 'غير معروف')
        start_time = s.get('start_time')
        if isinstance(start_time, datetime):
            start_time = start_time.strftime("%Y-%m-%d %H:%M:%S")
        resp = f"حالتك: `{status}`\nالمشروع: `{project}`\nبدأت: `{start_time}`"
        bot.send_message(chat_id, resp, parse_mode='Markdown')
    else:
        bot.send_message(chat_id, "❌ لا توجد جلسة نشطة. أرسل رابط Google Skills للبدء.", parse_mode='Markdown')

@bot.message_handler(func=lambda m: any(k in (m.text or "") for k in ['skills.google', 'google_sso', 'cloudskillsboost']))
def handle_skills_url(message):
    chat_id = message.chat.id
    skills_url = (message.text or "").strip()
    msg = bot.send_message(chat_id, "🔍 جاري تحليل الرابط...")
    try:
        deployer = CloudRunDeployer()
        creds = deployer.extract_credentials_from_url(skills_url)
        if not creds:
            bot.edit_message_text("❌ تعذر استخراج بيانات الاعتماد. أرسل رابط صحيح.", chat_id, msg.message_id)
            return
        user_sessions[chat_id] = {
            'credentials': creds,
            'status': 'analyzed',
            'message_id': msg.message_id,
            'start_time': datetime.now(),
            'username': message.from_user.username or "user"
        }
        bot.edit_message_text(
            f"✅ تم التحليل!\nالمشروع: `{creds['project_id']}`\nالبريد: `{creds['email']}`\nهل تود المتابعة بالمواصفات الافتراضية؟",
            chat_id, msg.message_id, parse_mode='Markdown',
            reply_markup=inline_confirm_markup()
        )
    except Exception as e:
        logger.error(f"❌ خطأ: {e}")
        bot.edit_message_text("❌ حدث خطأ أثناء المعالجة.", chat_id, msg.message_id)

def inline_confirm_markup():
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton("✅ نعم، تابع", callback_data="confirm_specs"),
               types.InlineKeyboardButton("❌ إلغاء", callback_data="cancel_creation"))
    return markup

@bot.callback_query_handler(func=lambda call: call.data == "confirm_specs")
def confirm_specs_callback(call):
    chat_id = call.message.chat.id
    if chat_id not in user_sessions:
        bot.answer_callback_query(call.id, "انتهت الجلسة.")
        return
    user_sessions[chat_id]['status'] = 'creating'
    bot.edit_message_text("🚀 جاري إنشاء الملفات... (خطوة للحزم والتجهيز)", chat_id, call.message.message_id)
    threading.Thread(target=create_v2ray_server, args=(chat_id, call.message.message_id), daemon=True).start()
    bot.answer_callback_query(call.id, "تم البدء")

@bot.callback_query_handler(func=lambda call: call.data == "cancel_creation")
def cancel_creation_callback(call):
    chat_id = call.message.chat.id
    user_sessions.pop(chat_id, None)
    bot.edit_message_text("❌ تم الإلغاء.", chat_id, call.message.message_id)
    bot.answer_callback_query(call.id, "ملغى")

def create_v2ray_server(chat_id, message_id):
    try:
        session = user_sessions.get(chat_id)
        if not session:
            bot.send_message(chat_id, "❌ الجلسة غير موجودة.")
            return
        creds = session['credentials']
        project_id = creds['project_id']
        server_name = f"v2ray-{uuid.uuid4().hex[:8]}"
        session['server_name'] = server_name

        bot.edit_message_text("🔧 إنشاء ملفات Docker و config...", chat_id, message_id)
        deployer = CloudRunDeployer()
        temp_dir = deployer.create_docker_image_files(server_name)
        if not temp_dir:
            raise Exception("فشل إنشاء ملفات التكوين.")

        bot.edit_message_text("📦 تحضير الأرشيف (ZIP) لإرساله...", chat_id, message_id)
        zip_path = os.path.join(temp_dir, f"{server_name}.zip")
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            for fname in os.listdir(temp_dir):
                if fname == f"{server_name}.zip":
                    continue
                zf.write(os.path.join(temp_dir, fname), arcname=fname)

        # محاولة نشر عبر gcloud إن أمكن
        service_url = deployer.deploy_to_cloud_run_if_possible(project_id, server_name, temp_dir)

        # إنشاء روابط VLESS و QR
        vless_links = generate_vless_config(service_url or f"{server_name}-{deployer.region}.local")

        session.update({
            'server_url': service_url,
            'vless_links': vless_links,
            'status': 'created' if service_url else 'packaged',
            'completion_time': datetime.now()
        })

        send_results(chat_id, message_id, service_url, vless_links, creds, server_name, zip_path)

    except Exception as e:
        logger.exception("❌ خطأ عام أثناء الإنشاء")
        user_sessions[chat_id]['status'] = 'failed'
        user_sessions[chat_id]['error'] = str(e)
        try:
            bot.send_message(chat_id, f"❌ حدث خطأ أثناء الإنشاء:\n`{str(e)[:300]}`", parse_mode='Markdown')
        except:
            pass
    finally:
        # تنظيف بعد زمن قصير (الملفات تبقى جاهزة للحالة اليدوية)
        pass

def generate_vless_config(service_url):
    domain = service_url.replace("https://", "").replace("http://", "").strip("/")
    # عند عدم وجود عنوان حقيقي نستخدم اسم مؤقت
    domain = domain or "example.com"
    vless_url = (
        f"vless://{V2RAY_CONFIG['uuid']}@{domain}:443"
        f"?type=ws&security=tls&path=%2F{V2RAY_CONFIG['path']}&host={domain}&sni={domain}&fp=chrome#GoogleCloud-V2Ray"
    )
    nekobox_config = {
        "v": "2",
        "ps": "Google Cloud Run V2Ray",
        "add": domain,
        "port": "443",
        "id": V2RAY_CONFIG['uuid'],
        "aid": "0",
        "scy": "auto",
        "net": "ws",
        "type": "none",
        "host": domain,
        "path": f"/{V2RAY_CONFIG['path']}",
        "tls": "tls",
        "sni": domain,
        "fp": "chrome"
    }
    config_json = json.dumps(nekobox_config)
    nekobox_url = "vless://" + base64.urlsafe_b64encode(config_json.encode()).decode()

    # QR
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_L)
    qr.add_data(vless_url)
    qr.make(fit=True)
    img = qr.make_image()
    img_bytes = BytesIO()
    img.save(img_bytes, format="PNG")
    img_bytes.seek(0)

    return {
        "vless_url": vless_url,
        "nekobox_url": nekobox_url,
        "v2rayn_config": {
            "remarks": "Google Cloud Run V2Ray",
            "address": domain,
            "port": 443,
            "id": V2RAY_CONFIG['uuid'],
            "alterId": 0,
            "security": "auto",
            "network": "ws",
            "path": f"/{V2RAY_CONFIG['path']}",
            "host": domain,
            "tls": "tls",
            "sni": domain
        },
        "qr_code_bytes": img_bytes,
        "domain": domain,
        "config_json": json.dumps({
            "server": domain,
            "port": 443,
            "uuid": V2RAY_CONFIG['uuid'],
            "path": V2RAY_CONFIG['path'],
            "security": "tls",
            "type": "ws",
            "sni": domain
        }, indent=2)
    }

def send_results(chat_id, message_id, service_url, vless_links, creds, server_name, zip_path=None):
    domain = vless_links['domain']
    vless_url = vless_links['vless_url']

    results_text = (
        f"✅ **تم تجهيز الملفات!**\n\n"
        f"👤 المستخدم: @{user_sessions[chat_id].get('username','user')}\n"
        f"📁 المشروع: `{creds['project_id']}`\n"
        f"🏷️ اسم الحزمة: `{server_name}`\n\n"
        f"🔗 رابط الخدمة (إن توفر): `{service_url if service_url else 'غير منشور تلقائياً'}`\n\n"
        f"🔑 **معلومات الاتصال:**\n• UUID: `{V2RAY_CONFIG['uuid']}`\n• Path: `/{V2RAY_CONFIG['path']}`\n• Port: 443\n• Security: TLS\n• Network: WebSocket\n• SNI: `{domain}`\n\n"
        f"🌐 **رابط VLESS كامل:**\n`{vless_url}`\n\n"
        "📎 أُرسِلَت مع هذه الرسالة: صورة QR وملف ZIP يحتوي على Dockerfile و config.json و README."
    )
    try:
        bot.send_message(chat_id, results_text, parse_mode='Markdown')
        # إرسال QR
        qr_bytes = vless_links['qr_code_bytes']
        qr_bytes.seek(0)
        bot.send_photo(chat_id, qr_bytes)

        # إرسال zip إن وُجد
        if zip_path and os.path.exists(zip_path):
            with open(zip_path, "rb") as f:
                bot.send_document(chat_id, f, caption="📦 ملفات Docker + config (ZIP)")
    except Exception as e:
        logger.error(f"❌ خطأ أثناء إرسال النتائج: {e}")

if __name__ == "__main__":
    logger.info("🔁 بدء البوت (polling)...")
    try:
        bot.infinity_polling(timeout=60, long_polling_timeout = 60)
    except KeyboardInterrupt:
        logger.info("⏹️ تم الإيقاف يدوياً.")
    except Exception as e:
        logger.exception("❌ خطأ في polling")
