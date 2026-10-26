# Running the lab on AWS (Jakarta region)

About 15 minutes in the AWS console, then 15 to 25 minutes of automatic install. Other platforms: [GCP](gcp-setup.md), [your own server](server-setup.md). Alerts: [Telegram](telegram-setup.md).

## 0. Enable the Jakarta region (once per account)

Jakarta (`ap-southeast-3`) is an opt-in region. If it is not in the region menu: account menu (top right) → **Account** → **AWS Regions** → Asia Pacific (Jakarta) → **Enable**. It takes a few minutes. Any other region works too; Jakarta just keeps the latency low for the demo.

## 1. Role that lets Systems Manager reach the VM

IAM → Roles → Create role → Trusted entity: **AWS service**, use case **EC2** → attach the managed policy **AmazonSSMManagedInstanceCore** → name it `relnusa-lab-ssm`.

This is also what allows Claude to run the install and fixes for you (option A), and it gives you a browser shell through Session Manager if SSH is ever blocked.

## 2. Launch the VM

EC2 → Region **Asia Pacific (Jakarta) ap-southeast-3** → Launch instance:

| Setting | Value |
|---|---|
| Name | `relnusa-lab` |
| AMI | Ubuntu Server 24.04 LTS, 64-bit (x86) |
| Instance type | `m7i.2xlarge` (8 vCPU, 32 GiB) |
| Key pair | create one and keep the `.pem` file |
| Network | default VPC, auto-assign public IP **enabled** |
| Security group | inbound **SSH (22)** from **Anywhere (0.0.0.0/0)**, because the venue's address is not known in advance; Ubuntu only accepts key logins. Add **443** too if you want SSH over port 443 at the venue (step 6) |
| Storage | 100 GiB gp3 |
| Advanced details → IAM instance profile | `relnusa-lab-ssm` |

Recommended, under Advanced details → **User data**, to install everything at first boot without logging in:

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | bash
```

Follow the install with `sudo tail -f /var/log/relnusa-lab-install.log`; it ends with `done`. The lab lives in `/opt/kai-workshop`. `./lab.sh` switches to root by itself, so you can run it as the `ubuntu` user.

## 3. Access for Claude (option A only)

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

## 4. Install (if you did not use user data)

```bash
ssh -i relnusa-lab.pem ubuntu@PUBLIC_IP
curl -fsSL https://raw.githubusercontent.com/adamnugraha/kai-workshop/main/bootstrap.sh | sudo bash
```

Then check it: `cd /opt/kai-workshop && ./lab.sh preflight`.

## 5. Open the dashboards from your laptop

Windows 10/11 (PowerShell), macOS and Linux all have OpenSSH:

```bash
ssh -i relnusa-lab.pem -N -L 8080:127.0.0.1:80 -L 9090:127.0.0.1:9090 ubuntu@PUBLIC_IP
```

Keep that window open, then use Chrome or Edge: `http://grafana.localhost:8080`, `http://app.localhost:8080`, `http://legacy.localhost:8080` and the others listed by `./lab.sh info`.

## 6. At the venue

Some guest Wi-Fi networks block port 22. Two fallbacks:

- Use your phone hotspot.
- Let SSH also listen on 443 (Ubuntu 24.04 uses socket activation), and open 443 in the security group:

```bash
sudo mkdir -p /etc/systemd/system/ssh.socket.d
printf '[Socket]\nListenStream=\nListenStream=22\nListenStream=443\n' | sudo tee /etc/systemd/system/ssh.socket.d/listen.conf
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
# then from the laptop:
ssh -i relnusa-lab.pem -p 443 -N -L 8080:127.0.0.1:80 -L 9090:127.0.0.1:9090 ubuntu@PUBLIC_IP
```

## 7. Cost and stopping

On-demand Linux price for `m7i.2xlarge` in Jakarta is listed at about USD 0.50 per hour (aws-pricing.com, checked 26 October 2026; confirm on the EC2 pricing page). The 100 GiB gp3 disk costs a few dollars a month. Stop the instance when you are not rehearsing; the lab comes back by itself on start, because the cluster containers restart with Docker. The public IP changes after a stop unless you attach an Elastic IP.

## 8. After the talk

Terminate the instance, delete the `claude-lab-operator` user (if created), the key pair and any Elastic IP.
