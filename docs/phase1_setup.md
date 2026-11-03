# VOC Pipeline — Phase 1 Setup Guide

Tài liệu hướng dẫn thiết lập môi trường Phase 1 đầy đủ.

---

## Mục lục

1. [Kiểm tra Python venv](#1-python-venv)
2. [Cài đặt AWS CLI](#2-aws-cli)
3. [Cài đặt Terraform](#3-terraform)
4. [Cấu hình .env](#4-env)
5. [Khởi động Airflow](#5-airflow)
6. [Tạo Airflow Fernet Key](#6-fernet-key)
7. [Chạy Smoke Test S3](#7-smoke-test)
8. [Checklist Phase 1](#8-checklist)

---

## 1. Python venv

venv đã có sẵn trong project. Kích hoạt và cài packages:

```powershell
# Kích hoạt venv
.\venv\Scripts\Activate.ps1

# Kiểm tra packages đã cài
pip list

# Nếu cần cài lại toàn bộ
pip install -r requirements.txt
```

---

## 2. AWS CLI

### Cài đặt

Tải MSI installer từ trang chính thức:

```
https://awscli.amazonaws.com/AWSCLIV2.msi
```

Hoặc dùng winget:

```powershell
winget install Amazon.AWSCLI
```

Sau khi cài, **mở lại terminal** và kiểm tra:

```powershell
aws --version
# aws-cli/2.x.x Python/3.x.x Windows/11 exe/AMD64
```

### Cấu hình credentials

> ⚠️ **Lưu ý:** Đối với CI/CD (GitHub Actions), sẽ dùng OIDC — không cần lưu key.  
> Credentials dưới đây CHỈ dùng cho local development.

```powershell
aws configure
# AWS Access Key ID [None]: <your_access_key>
# AWS Secret Access Key [None]: <your_secret_key>
# Default region name [None]: ap-southeast-1
# Default output format [None]: json
```

Kiểm tra:

```powershell
aws sts get-caller-identity
```

---

## 3. Terraform

### Cài đặt

**Option A — tfenv (khuyến nghị, quản lý version dễ hơn):**

```powershell
# Cài Chocolatey nếu chưa có
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Cài Terraform
choco install terraform -y
```

**Option B — Manual download:**

1. Tải binary từ: https://developer.hashicorp.com/terraform/install
2. Giải nén `terraform.exe` vào một thư mục trong PATH (ví dụ: `C:\terraform\`)
3. Thêm thư mục đó vào System PATH

Kiểm tra:

```powershell
terraform --version
# Terraform v1.9.x
```

---

## 4. Cấu hình .env

Copy file template và điền thông tin:

```powershell
Copy-Item .env.example .env
```

Mở `.env` và cập nhật:

```env
AWS_ACCESS_KEY_ID=your_actual_key
AWS_SECRET_ACCESS_KEY=your_actual_secret
AWS_DEFAULT_REGION=ap-southeast-1
S3_BUCKET=voc-analytics-dev
```

> 📌 `.env` đã được thêm vào `.gitignore` — không bao giờ commit file này.

---

## 5. Khởi động Airflow

### Bước 1: Tạo Fernet Key (một lần duy nhất)

```powershell
.\venv\Scripts\python.exe -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Copy kết quả vào `.env`:
```env
AIRFLOW__CORE__FERNET_KEY=<paste_here>
```

### Bước 2: Tạo Secret Key cho Webserver

```powershell
.\venv\Scripts\python.exe -c "import secrets; print(secrets.token_hex(32))"
```

Copy kết quả vào `.env`:
```env
AIRFLOW__WEBSERVER__SECRET_KEY=<paste_here>
```

### Bước 3: Tạo thư mục logs

```powershell
New-Item -ItemType Directory -Path "logs\airflow" -Force
```

### Bước 4: Khởi động

```powershell
docker compose up -d
```

Kiểm tra logs:

```powershell
docker compose logs -f airflow-scheduler
```

Sau ~30 giây, mở: **http://localhost:8080**  
Login: `airflow` / `airflow`

### Dừng Airflow

```powershell
docker compose down
```

---

## 6. Fernet Key (tham khảo)

Fernet Key được dùng để mã hóa connections và variables trong Airflow.  
Nếu mất key, tất cả secrets đã lưu sẽ không giải mã được.  
→ **Lưu key vào một nơi an toàn** (password manager).

---

## 7. Chạy Smoke Test S3

> ⚠️ **Yêu cầu:** `.env` đã được cấu hình đúng.  
> Bucket S3 chưa cần tồn tại (tạo trong Phase 2). Test sẽ kiểm tra credentials trước.

```powershell
.\venv\Scripts\Activate.ps1
python scripts/smoke_test_s3.py
```

Kết quả mong đợi:
- ✅ Credentials hợp lệ
- ⚠️ Bucket chưa tồn tại → bình thường, tạo trong Phase 2

---

## 8. Checklist Phase 1

| # | Mục | Trạng thái |
|---|-----|-----------|
| 1 | Python 3.12 + venv hoạt động | ✅ |
| 2 | `pip install -r requirements.txt` thành công | ⬜ |
| 3 | AWS CLI đã cài (`aws --version`) | ⬜ |
| 4 | `aws configure` đã chạy | ⬜ |
| 5 | `aws sts get-caller-identity` trả về account | ⬜ |
| 6 | Terraform đã cài (`terraform --version`) | ⬜ |
| 7 | `.env` đã tạo từ `.env.example` | ⬜ |
| 8 | Fernet Key đã tạo và điền vào `.env` | ⬜ |
| 9 | `docker compose up -d` thành công | ⬜ |
| 10 | Airflow UI mở được tại http://localhost:8080 | ⬜ |
| 11 | Smoke test: credentials OK | ⬜ |
| 12 | GitHub repo push lần đầu thành công | ⬜ |
| 13 | GitHub Actions CI chạy (dù có fail — bình thường) | ⬜ |

Khi hoàn thành tất cả → **Proceed to Phase 2 (AWS Foundation + Terraform)**
