import os
import requests

TG_BOT_TOKEN = os.getenv('TG_BOT_TOKEN')
TG_CHAT_ID = os.getenv('TG_CHAT_ID')
WEBHOOK_URL = os.getenv('ALERT_WEBHOOK_URL')


def send_telegram_alert(message: str) -> bool:
    """Send a Telegram message if configured; otherwise POST to a webhook if provided."""
    sent = False
    if TG_BOT_TOKEN and TG_CHAT_ID:
        url = f"https://api.telegram.org/bot{TG_BOT_TOKEN}/sendMessage"
        try:
            r = requests.post(url, json={"chat_id": TG_CHAT_ID, "text": message}, timeout=5)
            sent = r.ok
        except Exception:
            sent = False
    elif WEBHOOK_URL:
        try:
            r = requests.post(WEBHOOK_URL, json={"text": message}, timeout=5)
            sent = r.ok
        except Exception:
            sent = False
    else:
        print("No alerting backend configured; message:", message)
        sent = True
    return sent
