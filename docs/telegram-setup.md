# Telegram alerts

The lab sends SLO alerts (and only those) to Telegram through Alertmanager. Setup takes about 10 minutes on your phone or Telegram Desktop.

## 1. Create the bot

1. Open a chat with **@BotFather** (the official one, with the blue tick).
2. Send `/newbot`.
3. Display name: for example `RelNusa Lab Alerts`.
4. Username: must end in `bot`, for example `relnusa_lab_alerts_bot`.
5. BotFather replies with a **token** like `1234567890:AAH...`. Treat it like a password.

## 2. Choose where the alerts go

| Option | Good for | Note |
|---|---|---|
| **Channel** (recommended for the audience) | Many people watching; only the bot posts | Subscribers do not see each other. The bot must be an **administrator** of the channel with permission to post |
| **Group** | A small team that wants to discuss alerts | Members see each other's names. The bot only needs to be a member |

**Channel:** Telegram → New Channel → name it (for example `RelNusa Lab · Peringatan`) → Private → skip adding people. Channel → Administrators → Add Admin → search the bot's username → keep **Post Messages** on → Save. Then post any message in the channel, for example `halo`.

**Group:** New Group → add the bot → create. Then send any message in the group.

## 3. Find the chat ID

In a browser, open (with your token):

```
https://api.telegram.org/bot<TOKEN>/getUpdates
```

Look for `"chat":{"id":-100...` in the response. That negative number is the **chat ID**, including the minus sign. For a channel it appears under `channel_post`; for a group, under `message` or `my_chat_member`.

If the result is empty (`"result":[]`), post another message in the channel or group and reload. Telegram keeps these updates for 24 hours.

## 4. Put both values on the lab VM

```bash
cd /opt/kai-workshop            # or wherever the lab is
nano lab.env
```

```
TELEGRAM_BOT_TOKEN=1234567890:AAH...
TELEGRAM_CHAT_ID=-1001234567890
```

Then:

```bash
./lab.sh alerts                 # reloads Alertmanager with the Telegram route (about a minute)
./lab.sh telegram-test          # a test message should arrive within about 15 seconds
```

## 5. Let the audience join (optional)

Channel or group → Invite links → create a link. Put it on a slide as a QR code so people can join at the start of the talk and receive the alerts during the game day.

## 6. After the event

In @BotFather: `/revoke` gives the bot a new token (the old one stops working), or `/deletebot` removes it. Archive or delete the channel if it is no longer needed.

## Troubleshooting

| Symptom | Check |
|---|---|
| `telegram-test` reports ok but nothing arrives | Wrong chat ID (it must include the minus sign), or the bot is not an admin of the channel |
| Alertmanager logs `Forbidden: bot is not a member` | Add the bot to the group, or as channel administrator |
| The chat ID changed | Converting a group to a supergroup gives it a new `-100...` ID; read it again with `getUpdates` |
| Real alerts do not arrive | Only alerts that carry an SLO label are routed to Telegram; check *RelNusa · 2* for active alerts |
