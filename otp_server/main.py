import asyncio
import re
import os
import json
import logging
from datetime import datetime, timezone
from fastapi import FastAPI, Query
from aioimaplib import aioimaplib
import httpx
from typing import List, Optional

# --- Configuration ---
# Set these in Koyeb Environment Variables
ACCOUNTS_JSON = os.getenv("ACCOUNTS_JSON", "[]") # Format: [{"email": "...", "password": "..."}, ...]
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")
OTP_REGEX = r"【パスコード】\s*(\d{6})"

# --- Setup Logging ---
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("OTP_SERVER")

app = FastAPI(title="Professional OTP Server")
LATEST_OTPS = {} # email -> {code, subject, timestamp}

async def send_telegram_msg(msg: str):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        async with httpx.AsyncClient() as client:
            await client.post(url, json={"chat_id": TELEGRAM_CHAT_ID, "text": msg})
    except Exception as e:
        logger.error(f"Failed to send Telegram message: {e}")

async def monitor_email(email_user: str, password: str, host: str = "imap.gmail.com"):
    logger.info(f"Starting monitor for {email_user}")
    
    while True:
        client = aioimaplib.IMAP4_SSL(host=host)
        try:
            await client.wait_hello()
            await client.login(email_user, password)
            await client.select("INBOX")
            
            logger.info(f"Connected and IDLE started for {email_user}")
            
            while True:
                # Start IDLE
                idle_task = await client.idle_start()
                
                # Wait for changes or timeout (to avoid ghost connections)
                try:
                    await asyncio.wait_for(client.wait_server_push(), timeout=300)
                except asyncio.TimeoutError:
                    pass
                
                # Stop IDLE to process
                client.idle_done()
                
                # Search for new messages
                # For simplicity, we check the latest message
                res, data = await client.uid("SEARCH", "ALL")
                if res == "OK":
                    uids = data[0].split()
                    if uids:
                        latest_uid = uids[-1].decode()
                        res, msg_data = await client.uid("FETCH", latest_uid, "(BODY.PEEK[TEXT] BODY.PEEK[HEADER.FIELDS (SUBJECT)])")
                        
                        if res == "OK":
                            raw_content = "".join([str(part) for part in msg_data])
                            match = re.search(OTP_REGEX, raw_content)
                            if match:
                                code = match.group(1)
                                
                                # Check if it's a new code for this email
                                if LATEST_OTPS.get(email_user, {}).get("code") != code:
                                    logger.info(f"🔥 NEW OTP for {email_user}: {code}")
                                    LATEST_OTPS[email_user] = {
                                        "code": code,
                                        "timestamp": datetime.now(timezone.utc).isoformat(),
                                        "email": email_user
                                    }
                                    
                                    # Notify via Telegram
                                    msg = f"📩 OTP Pokemon Center\n📧 Email: {email_user}\n🔑 Code: {code}\n⏰ {datetime.now().strftime('%H:%M:%S')}"
                                    await send_telegram_msg(msg)

        except Exception as e:
            logger.error(f"Error in monitor for {email_user}: {e}")
            await asyncio.sleep(10) # Wait before reconnecting
        finally:
            try:
                await client.logout()
            except:
                pass

@app.on_event("startup")
async def startup_event():
    try:
        accounts = json.loads(ACCOUNTS_JSON)
        for acc in accounts:
            asyncio.create_task(monitor_email(acc["email"], acc["password"]))
    except Exception as e:
        logger.error(f"Failed to parse ACCOUNTS_JSON: {e}")

@app.get("/")
async def root():
    return {"status": "running", "monitors": len(LATEST_OTPS), "latest": LATEST_OTPS}

@app.get("/otp")
async def get_otp(email: str = Query(...)):
    otp_data = LATEST_OTPS.get(email)
    if otp_data:
        return otp_data
    return {"status": "not_found"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8000)))
