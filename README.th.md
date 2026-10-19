# OllamaBar

[English](README.md) | **ไทย**

[![build](https://github.com/yutna/ollama-bar/actions/workflows/build.yml/badge.svg)](https://github.com/yutna/ollama-bar/actions/workflows/build.yml)
[![release](https://img.shields.io/github/v/release/yutna/ollama-bar)](https://github.com/yutna/ollama-bar/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

ปุ่มเปิด/ปิด **Ollama server** บนเครื่องของคุณ ผ่านเมนูบาร์ macOS —
เปิดเมื่อใช้ ปิดเมื่อเลิกใช้ แล้วได้ RAM คืนทันที

ปกติ Ollama จะติดตั้งตัวเองเป็น service ที่รันเบื้องหลังตลอดเวลา บนโน้ตบุ๊ก
นั่นหมายถึงโมเดลขนาดหลายกิกะไบต์จะกิน unified memory อยู่ตลอดแม้คุณเลิกใช้ไปนานแล้ว
OllamaBar เปลี่ยนให้เหลือแค่คลิกเดียว:

![เมนู OllamaBar](docs/menu-th.png)

| การทำงาน | เกิดอะไรขึ้น |
| --- | --- |
| **▶︎ เริ่ม Ollama** | รัน `ollama serve` พร้อมค่าที่ปรับมาแล้ว (ดูด้านล่าง) |
| **🔥 โหลดโมเดลล่วงหน้า** | โหลดโมเดลแรกที่ติดตั้งไว้ล่วงหน้า คำขอแรกจะไม่มีดีเลย์ |
| **■ หยุด Ollama** | unload ทุกโมเดลและปิด server — คืน RAM ทันที |
| **ออก** | ปิด Ollama ด้วย (ไม่มีอะไรค้างอยู่ในเบื้องหลัง) |

ค่าเริ่มต้นคือไม่ตั้งให้ทำงานอัตโนมัติตอนบูตเลย ไอคอนบนเมนูบาร์คือจุดเดียวที่คุณแตะ
ส่วน "แสดงไอคอนตอนล็อกอิน" จะเปิดแค่ *ไอคอน* — ตัว server ยังต้องกดเริ่มเองเท่านั้น

## ฟีเจอร์

- คลิกเดียวเปิด/ปิด `ollama serve`
- ปุ่ม **หยุด** คืน memory ทันที ไม่ต้องรอ keep-alive timeout
- ค่าเริ่มต้นที่เหมาะกับงานจริง: keep-alive `-1`, context 64k, โหลดทีละโมเดล
- ปุ่ม warm-up โหลดโมเดลก่อนเปิด editor
- "แสดงไอคอนตอนล็อกอิน" แบบเลือกได้ (เฉพาะไอคอน — Ollama ยังไม่ทำงานจนกว่าจะกดเริ่ม)
- โหมด CLI สำหรับ script (`--start`, `--stop`, `--status`, `--warm`, `--help`)
- UI หลายภาษา (English / ไทย) ตามภาษาของระบบ
- หา Ollama เจอไม่ว่าจะติดตั้งที่ไหน: Homebrew (Apple Silicon หรือ Intel) หรือแอปทางการ

## ความต้องการของระบบ

- macOS 13 (Ventura) ขึ้นไป
- ติดตั้ง [Ollama](https://ollama.com) แล้ว (แอปทางการหรือ Homebrew)
- ถ้าจะ build เอง: Xcode Command Line Tools (`xcode-select --install`)

## การติดตั้ง

### ดาวน์โหลด

ดาวน์โหลด `OllamaBar.app.zip` จาก [release ล่าสุด](https://github.com/yutna/ollama-bar/releases/latest)
แตกไฟล์ แล้วย้าย `OllamaBar.app` ไปไว้ใน `/Applications` ตัว build เป็น
universal binary (Apple Silicon + Intel) และเซ็นแบบ ad-hoc ดังนั้น Gatekeeper
อาจถามยืนยันตอนเปิดครั้งแรก หรือจะล้าง quarantine flag เองก็ได้:

```sh
xattr -dr com.apple.quarantine /Applications/OllamaBar.app
```

### Build จากซอร์ส

```sh
git clone https://github.com/yutna/ollama-bar.git
cd ollama-bar
make install              # build แล้วติดตั้งไป /Applications
# หรือ: PREFIX=~/Applications make install
```

จากนั้นเปิด **OllamaBar** และมองหาไอคอน 🦙 บนเมนูบาร์

เป้าหมายอื่นๆ ของ make: `build`, `run`, `lint`, `format`, `release-zip`, `uninstall`

## วิธีใช้

1. คลิกไอคอน 🦙
2. เลือก **เริ่ม Ollama**
3. ถ้าต้องการ เลือก **โหลดโมเดลล่วงหน้า**
4. เปิด editor / coding agent (OpenCode, Claude Code, [`ollama launch`](https://docs.ollama.com/integrations), …) แล้วทำงานได้เลย
5. เลิกใช้แล้วคลิก 🦙 → **หยุด Ollama** ได้ RAM คืนทันที

ไอคอนจะจางลงเมื่อ server หยุดอยู่

## ค่าเริ่มต้น

ค่าต่อไปนี้จะถูกใช้กับ server ที่ OllamaBar เป็นตัวเปิด:

| ค่า | ค่าที่ตั้ง | เหตุผล |
| --- | --- | --- |
| `OLLAMA_KEEP_ALIVE` | `-1` | ให้โมเดลอยู่ใน memory ตลอด session (ไม่ต้องโหลดใหม่) |
| `OLLAMA_CONTEXT_LENGTH` | `65536` | [Ollama แนะนำ 64k+](https://docs.ollama.com/context-length) สำหรับ agent/เครื่องมือเขียนโค้ด |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | กันไม่ให้โมเดลที่สองมากิน unified memory |
| `OLLAMA_FLASH_ATTENTION` | `1` | (backend llama.cpp) |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | (backend llama.cpp) |

ถ้ารัน binary เอง สามารถ override ผ่าน environment variable ได้:

```sh
OLLAMABAR_CONTEXT_LENGTH=32768 ./build/OllamaBar.app/Contents/MacOS/OllamaBar --start
```

ค่าที่ override ได้: `OLLAMABAR_PORT`, `OLLAMABAR_KEEP_ALIVE`,
`OLLAMABAR_CONTEXT_LENGTH`, `OLLAMABAR_MAX_LOADED_MODELS`,
`OLLAMABAR_FLASH_ATTENTION`, `OLLAMABAR_KV_CACHE_TYPE`

## โหมด CLI

เหมาะกับ script หรือ shell alias:

```sh
BIN=/Applications/OllamaBar.app/Contents/MacOS/OllamaBar
$BIN --start    # เปิด server ด้วยค่าที่ปรับไว้
$BIN --status   # stopped | running | running model-loaded
$BIN --warm     # โหลดโมเดลแรกที่ติดตั้งไว้ล่วงหน้า
$BIN --stop     # unload โมเดล + ปิด server
```

CLI จะตอบเป็นภาษาอังกฤษเสมอ เพื่อให้ script ไม่ต้อง parse ข้อความที่แปลแล้ว

## กลไกภายใน

- **เริ่ม** spawn `ollama serve` เป็น child process พร้อม environment ด้านบน
  และเขียน log ไปที่ `~/.ollama/logs/server.log`
- **หยุด** สั่ง Ollama unload โมเดลที่โหลดอยู่ทีละตัว แล้วปิด server
  (รวมถึง `ollama serve` / `ollama runner` ที่ผู้ใช้เป็นเจ้าของทุกตัว เพื่อให้ได้ RAM คืนแน่นอน)
- ตัวแอปถูกเซ็นแบบ ad-hoc ตอน build

## หลายภาษา

UI มีให้เลือกสองภาษา: อังกฤษและไทย (`resources/<ภาษา>.lproj/Localizable.strings`)
โดยตามภาษาของระบบ การเพิ่มภาษาอื่นทำได้แค่วางโฟลเดอร์ `.lproj` ใหม่ — ยินดีรับ PR

## หมายเหตุและข้อจำกัด

- โปรเจกต์นี้ไม่มีความเกี่ยวข้องกับ [Ollama](https://ollama.com) — เป็นแค่ตัวช่วยครอบ CLI ที่คุณมีอยู่แล้ว
- **หยุด** จะปิด `ollama serve` ทุกตัวที่เป็นของผู้ใช้คนนี้ รวมถึงตัวที่เปิดเองจากข้างนอก
  (เช่น `brew services`) ถ้าคุณใช้ background service อยู่แล้ว ก็ไม่ต้องรันทั้งสองอย่าง
- แอปนี้จัดการแค่ lifecycle ของ server — การ pull โมเดลและไฟล์ config ยังใช้ Ollama ปกติ (`ollama pull …`, `~/.ollama/…`)

## การมีส่วนร่วม

ยินดีรับ issue และ pull request — อ่านรายละเอียดได้ที่ [CONTRIBUTING.md](CONTRIBUTING.md)
และ [Code of Conduct](CODE_OF_CONDUCT.md) มีผลกับทุกพื้นที่ของโปรเจกต์
สำหรับการรายงานด้านความปลอดภัย ดู [SECURITY.md](SECURITY.md)

## สัญญาอนุญาต

[MIT](LICENSE) © Yutthana Siphuengchai
