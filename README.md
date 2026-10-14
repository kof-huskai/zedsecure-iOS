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

## وضعیت فعلی

- ✅ UI، مدیریت سرورها، چسباندن لینک از کلیپ‌بورد
- ✅ تبدیل لینک به کانفیگ sing-box (`Shared/ConfigBuilder.swift`): `vless`، `vmess`، `trojan`، `ss`، `hysteria2`/`hy2` (روی TCP/WS/gRPC/HTTP/HTTPUpgrade، با TLS و Reality)
- ✅ هسته‌ی sing-box (libbox، نسخه‌ی پین‌شده‌ی `v1.13.21`) در CI ساخته و به افزونه‌ی تونل وصل می‌شود
- ⏳ **هنوز روی دستگاه واقعی تست نشده.** کد Swift را فقط CI کامپایل می‌کند.

لینک‌هایی که هنوز پشتیبانی نمی‌شوند (به‌جای کانفیگ اشتباه، خطای روشن می‌دهند): XHTTP، VLESS encryption، افزونه‌های Shadowsocks، `pinSHA256` در Hysteria2، TCP با header اچ‌تی‌تی‌پی. TUIC و WireGuard هنوز اضافه نشده‌اند.

## CI

کارهای workflow `Build (unsigned)`:

1. `libbox`: ساخت هسته‌ی sing-box برای iOS (بار اول حدود ۱۰ تا ۲۰ دقیقه، بعد از آن cache می‌شود)
2. `config-tests`: تست‌های `Tests/main.swift` روی ConfigBuilder
3. `config-check`: کانفیگ‌های تولیدشده را با خود `sing-box check` اعتبارسنجی می‌کند
4. `build`: ساخت اپ و افزونه

## نقشه‌ی راه
1. ✅ اسکلت + CI
2. ✅ وصل کردن sing-box و ConfigBuilder
3. تست روی دستگاه (امضا با اکانت پولی، TestFlight) و رفع خطاها
4. import اشتراک (subscription)، QR، تست سرعت، انتخاب خودکار سریع‌ترین سرور
5. Xray (libXray) برای XHTTP و بقیه، سپس موتورهای دیگر

## لایسنس
اگر از کد ZedSecure (AGPL-3.0) کپی کنید، این پروژه هم باید AGPL-3.0 و متن‌باز باشد. sing-box هم GPL-3.0 است. فایل `LICENSE` را قبل از انتشار اضافه کنید.
