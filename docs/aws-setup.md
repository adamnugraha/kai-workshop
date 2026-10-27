# Running the lab on AWS (Jakarta region)

About 15 minutes in the AWS console, then 15 to 25 minutes of automatic install. Other platforms: [GCP](gcp-setup.md), [your own server](server-setup.md). Alerts: [Telegram](telegram-setup.md).

By default the lab opens at the VM's public IP, for example `https://app.203.0.113.10.sslip.io`, with no SSH tunnel. [sslip.io](https://sslip.io) is a free DNS service that answers any `<name>.<ip>.sslip.io` with that IP, so there is no DNS to set up. The lab gets free Let's Encrypt certificates for these names by itself; `http://` works too.

## 0. Enable the Jakarta region (once per account)

Jakarta (`ap-southeast-3`) is an opt-in region. If it is not in the region menu: account menu (top right) → **Account** → **AWS Regions** → Asia Pacific (Jakarta) → **Enable**. It takes a few minutes. Any other region works too; Jakarta just keeps the latency low for the demo.

## 1. Role that lets Systems Manager reach the VM

IAM → Roles → Create role → Trusted entity: **AWS service**, use case **EC2** → attach the managed policy **AmazonSSMManagedInstanceCore** → name it `relnusa-lab-ssm`.

This gives you a browser shell (Session Manager) if SSH is ever blocked, and it is what lets Claude run the install for you (option A).

## 2. Launch the VM

EC2 → Region **Asia Pacific (Jakarta) ap-southeast-3** → Launch instance:

| Setting | Value |
|---|---|
| Name | `relnusa-lab` |
| AMI | Ubuntu Server 24.04 LTS, 64-bit (x86) |
| Instance type | `m7i.2xlarge` (8 vCPU, 32 GiB) |
| Key pair | create one and keep the `.pem` file |
| Network | default VPC, auto-assign public IP **enabled** |
| Security group | inbound **SSH (22)**, **HTTP (80)** and **HTTPS (443)**, all from **Anywhere (0.0.0.0/0)**. The venue's address is not known in advance; Ubuntu only accepts key logins, the lab's operator tools ask for a password, and Let's Encrypt checks port 80 before it issues the certificates |
| Storage | 100 GiB gp3 |
| Advanced details → IAM instance profile | `relnusa-lab-ssm` |
| Advanced details → User data | the script below |

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | bash
```

To keep everything on 127.0.0.1 and use an SSH tunnel instead, put `export LAB_ACCESS=tunnel` on the line before `curl`. You can pass Telegram settings the same way (`export TELEGRAM_BOT_TOKEN=...` and `export TELEGRAM_CHAT_ID=...`).

## 3. Give it a fixed address (recommended)

EC2 → **Elastic IPs** → Allocate → Actions → **Associate** with `relnusa-lab`. The addresses then stay the same after the VM is stopped and started, so bookmarks and QR codes keep working. Without it, the lab still works after a restart; it just moves to the new IP by itself.

## 4. Check the install

The install runs by itself for 15 to 25 minutes after launch. To follow it:

```bash
ssh -i relnusa-lab.pem ubuntu@PUBLIC_IP
sudo tail -f /var/log/relnusa-lab-install.log     # each step starts with "=="; the last line says "done" (Ctrl+C stops watching)
```

If a step fails, the log says `FAILED during: ...` with the reason just above it. After fixing the cause, `sudo bash /opt/kai-workshop/bootstrap.sh` continues from there. If you skipped the user data, install by hand: `curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | sudo bash`.

When the log says "done":

```bash
cd /opt/kai-workshop
./lab.sh preflight                                # must end with "ready"
./lab.sh info                                     # the addresses and the password
```

`./lab.sh` switches to root by itself, so the `ubuntu` user is fine.

Then test it from outside your own network, for example in Google Cloud Shell or any other machine on the internet:

```bash
IP=PUBLIC_IP
curl -s -o /dev/null -w 'http  %{http_code}\n' http://app.$IP.sslip.io/
curl -s -o /dev/null -w 'https %{http_code}\n' https://app.$IP.sslip.io/
```

Both lines should end in 200. If they do but your laptop cannot open the page, your office network is blocking it; try your phone on mobile data.

**Instance made with an earlier version of this guide** (no HTTPS): add an inbound rule for **HTTPS (443)** from Anywhere to its security group, then run `cd /opt/kai-workshop && sudo git pull && ./lab.sh apply` on the VM. It keeps the data and takes a few minutes. (Later updates are just `./lab.sh update`; older copies of the script do not have that command yet.)

## 5. Open the lab

Open the addresses from `./lab.sh info` in any browser, including a phone:

| Address | What | Login |
|---|---|---|
| `https://app.<ip>.sslip.io` | Modern site | none |
| `https://legacy.<ip>.sslip.io` | Legacy site | none |
| `https://grafana.<ip>.sslip.io` | Dashboards | view without login; `admin` to edit |
| `https://jaeger.`, `chaos.`, `rollouts.`, `prometheus.`, `alertmanager.<ip>.sslip.io` | Operator tools | `admin` and the password from `./lab.sh info` |

You still need SSH for the terminal that runs the demo commands.

If `./lab.sh info` still shows `http://` addresses, the certificates have not been issued yet; `./lab.sh preflight` says why (usually port 80 or 443 closed in the security group).

## 6. Access for Claude (option A only)

IAM → Users → Create user `claude-lab-operator`, no console access. Add an inline policy with the JSON below, replacing `ACCOUNT_ID` and `INSTANCE_ID`. Then Security credentials → Create access key (use case "Other") and paste the key ID and secret into the chat.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "RunCommandsOnLabVmOnly", "Effect": "Allow", "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ec2:ap-southeast-3:ACCOUNT_ID:instance/INSTANCE_ID",
        "arn:aws:ssm:ap-southeast-3::document/AWS-RunShellScript" ] },
    { "Sid": "ReadResults", "Effect": "Allow",
      "Action": [ "ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:CancelCommand",
                  "ssm:DescribeInstanceInformation", "ec2:DescribeInstances" ],
      "Resource": "*" },
    { "Sid": "StartStopLabVm", "Effect": "Allow",
      "Action": [ "ec2:StartInstances", "ec2:StopInstances" ],
      "Resource": "arn:aws:ec2:ap-southeast-3:ACCOUNT_ID:instance/INSTANCE_ID" }
  ]
}
```

The key can only run commands on that one VM and start or stop it. Delete the user after the talk.

## 7. At the venue

- **Port 22 blocked on the guest Wi-Fi:** use the browser shell instead: EC2 → select the instance → **Connect** → **Session Manager**. It runs over HTTPS. Then `sudo -i -u ubuntu` and `cd /opt/kai-workshop`.
- **The sslip.io names do not resolve:** a few corporate DNS filters block wildcard DNS services. Use your phone hotspot, or set your own domain: point a wildcard record `*.lab.example.com` at the Elastic IP, put `LAB_DOMAIN=lab.example.com` in `lab.env`, and run `./lab.sh update-ip`.
- **A page does not open over `https://`, or shows a certificate warning:** use the same address with `http://`, then run `./lab.sh preflight`.
- **Test it the day before** from a network other than your office, ideally from your phone on mobile data.

## 8. Cost and stopping

The on-demand Linux price for `m7i.2xlarge` in Jakarta is USD 0.504 per hour in the AWS price list (checked 27 October 2026). The 100 GiB gp3 disk and the Elastic IP add a few dollars a month. Stop the instance when you are not rehearsing. After a start, a boot service brings the cluster back and, without an Elastic IP, moves the addresses to the new IP. Give it about five minutes, then run `./lab.sh preflight` (if a node still shows as not ready, run `./lab.sh restart`).

## 9. After the talk

Terminate the instance, then delete the `claude-lab-operator` user (if created), the key pair, and release the Elastic IP (it is billed while it exists).
