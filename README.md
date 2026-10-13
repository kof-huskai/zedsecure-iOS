# ZedSecure iOS (پورت)

پورت iOS برای کلاینت VPN، ساخته‌شده کاملاً روی GitHub Actions (بدون نیاز به Mac).

> این پروژه یک اسکلت است. فعلاً UI، مدیریت سرورها و Packet Tunnel (بدون هسته) را دارد. اتصال واقعی بعد از وصل کردن sing-box (مرحله ۲) کار می‌کند.

## مراحل راه‌اندازی

### ۱. تنظیم شناسه‌ها
در `project.yml` و `Shared/Constants.swift` مقدار `com.example` و `group.com.example.zedsecureios` را با شناسه‌ی خودتان عوض کنید (هر سه جا باید یکی باشد).

### ۲. پورتال Apple Developer (فقط یک‌بار، از مرورگر)
1. حساب پولی Apple Developer Program بگیرید.
2. در Identifiers دو App ID بسازید: `…zedsecureios` و `…zedsecureios.PacketTunnel`.
3. روی هر دو قابلیت **Network Extensions** و **App Groups** را فعال کنید و یک App Group به نام `group.…` بسازید و به هر دو وصل کنید.
4. در App Store Connect → Users and Access → Integrations یک **API Key** با نقش Admin یا App Manager بسازید و فایل `.p8` را نگه دارید.

### ۳. Secrets در GitHub
Settings → Secrets and variables → Actions:

| نام | مقدار |
|---|---|
| `APPLE_TEAM_ID` | Team ID ده‌حرفی |
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | کل محتوای فایل `.p8` |

### ۴. ساخت
- **Build (unsigned):** با هر push اجرا می‌شود و فقط بررسی می‌کند پروژه کامپایل می‌شود.
- **Release (signed IPA):** از تب Actions دستی اجرا کنید (یا تگ `v0.1.0` بزنید). خروجی IPA امضاشده و در حالت `app-store-connect` آپلود خودکار به TestFlight است.

## نقشه‌ی راه
1. ✅ اسکلت + CI
2. وصل کردن sing-box (`tools/build-cores.sh` → `Libbox.xcframework` → PlatformInterface در `PacketTunnelProvider`)
3. تبدیل لینک‌های share به کانفیگ sing-box (`ConfigBuilder`)
4. import اشتراک، QR، تست سرعت
5. Xray (libXray) و بقیه‌ی موتورها

## لایسنس
اگر از کد ZedSecure (AGPL-3.0) کپی کنید، این پروژه هم باید AGPL-3.0 و متن‌باز باشد. sing-box هم GPL-3.0 است. فایل `LICENSE` را قبل از انتشار اضافه کنید.
