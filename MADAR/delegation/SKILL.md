---
name: madar-delegation
description: "Orchestrate multi-model AI delegation in MADAR POS/ERP. Pairs deep architectural thinking models (Claude Opus, Claude Sonnet, Gemini 4 Argon / Gemini Pro) with high-speed execution models (Gemini 3.8 Flash) and an autonomous fleet of rotating free OpenCode Zen models (big-pickle, deepseek-v4.1-flash-free, glm-5.3-flash-free, nemotron-3.5-lightning-free). Enforces strict token-shielding (delta-only reviews) and automated bidirectional sync with Notion Tasks."
---

# MADAR Multi-Model Delegation Skill & SOP

نظام وميثاق التفويض متعدد الوكلاء (Multi-Model Delegation Framework) الخاص بمشروع **MADAR ERP / POS Offline Desktop**.

---

## 1. أسطول الموديلات المجانية في OpenCode (Free Model Fleet & Dynamic Rotation)

بدلاً من الاعتماد على موديل واحد فقط (`big-pickle`)، يمتلك نظام التفويض أسطولاً متكاملاً من **موديلات OpenCode Zen المجانية تماماً ($0.00)**، يتم الاختيار منها بمرونة والتناوب بينها حسب نوع المهمة:

| الموديل | التخصص الأمثل | متى يختاره الوكيل؟ |
|---|---|---|
| **`opencode/big-pickle`** | مهندس الاختبارات وحلقات العمل الذاتية | كتابة ملفات الـ Unit Tests الشاملة وتشغيلها وفحص نتائجها |
| **`opencode/deepseek-v4.1-flash-free`** | المنطق الرياضي والخوارزميات الدقيقة | كتابة الخدمات الحسابية (Services)، معادلات التسعير، ودوال الـ FIFO |
| **`opencode/glm-5.3-flash-free`** | الكود السريع والدعم متعدد اللغات (عربي) | إنشاء الـ DAOs المكررة، الواجهات، وكود الـ Boilerplate مع دعم العربية |
| **`opencode/nemotron-3.5-lightning-free`** | التعديلات السريعة وفائقة الخفة | الفحوصات الخفيفة، إعادة التسمية (Refactoring)، وتنظيف الـ Lints |
| **`opencode/mimo-v2.6-flash-free`** | الموديل البديل والاحتياطي | يعمل كـ Fallback سريع لو كان أي موديل آخر مشغولاً |

### سلم التناوب والتبديل التلقائي عند الضغط (Failover Rotation):
إذا واجه الموديل الأول أي تأخير أو ضغط مؤقت في OpenCode Zen، يتم التبديل التلقائي بالترتيب:
$$\text{big-pickle} \longleftrightarrow \text{deepseek-v4.1-flash-free} \longleftrightarrow \text{glm-5.3-flash-free} \longleftrightarrow \text{nemotron-3.5-lightning-free}$$

---

## 2. أتمتة الربط مع Notion (Automated Notion Pipeline)

النظام مربوط بالكامل مع قاعدة بيانات **`✅ Tasks — المهام المركزية`** في Notion (`Database ID: 1ab4c829-3bd9-47e6-a2cd-55a65d7a2dcb`):

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. السحب التلقائي (Pull from Notion - Task Intake)                          │
│  - يقرأ الوكيل أي مهمة في Notion حالتها: "Ready for Delegation"              │
│  - يستخرج المتطلبات وشروط القبول تلقائياً دون الحاجة لكتابتها في الشات       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼ (تشغيل دورة الـ Delegation)
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. التنفيذ المتوازي (Parallel Execution)                                    │
│  - Flash ينفذ المنطق في lib/                                                │
│  - OpenCode ينفذ الاختبارات بموديل مجاني من الأسطول (big-pickle / deepseek)  │
│  - الموديل الثقيل (Argon / Opus) يراجع فوارق الـ Diff فقط (< 500 توكن)      │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼ (تحديث Notion التلقائي)
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. التوثيق والإغلاق في Notion (Push to Notion - Auto-Logging)               │
│  - تحديث حالة المهمة في Notion إلى: Done                                    │
│  - تسجيل أسطول الموديلات المستخدمة والتكلفة: $0.00                           │
│  - إرفاق نتيجة الاختبارات (مثلاً: 16/16 Passed) وفارق الـ Diff المعتمد      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. بروتوكول حماية التوكنز وفحص الفوارق فقط (Delta-Only Token Shield)

> ⚠️ **القاعدة الصارمة لحماية الليمت (Strict Token Budget Invariant):**
> **ممنوع نهائياً** تمرير ملفات كاملة (500-2000 سطر) أو جعل الموديل الثقيل (**Gemini 4 Argon / Claude Opus**) يبحث داخل مجلدات المشروع أو يقرأ كوداً كاملاً.
> الموديل الثقيل صُمم ليكون **"قاضياً فائق الذكاء يراجع الفارق المعدل فقط (Diff Delta)"** بأقل من 500 توكن بعد أن يتأكد Flash أو OpenCode من نظافة الكود واجتياز كل الاختبارات.

---

## 4. صيغة الأمر المعتمدة للمحادثات الجديدة (Universal Prompt)

إذا فتحت **Conversation جديدة تماماً** في Antigravity، انسخ والصق هذه الصيغة في رسالتك الأولى:

```text
اقرأ مهارة التفويض في: MADAR/delegation/SKILL.md
عندي ميزة [اكتب اسم الميزة هنا، أو اكتب: "اسحب المهمة المفتوحة من Notion"]:
1. الموديل الخفيف (Gemini 3.8 Flash): اقرأ الملفات ذات الصلة، واكتب كود المنطق والـ Service في lib/، وتأكد من خلوه من أخطاء الـ analyze.
2. مهندس الاختبارات: اختر موديل مجاني مناسب من أسطول OpenCode Zen (مثل big-pickle أو deepseek-v4.1-flash-free أو glm-5.3-flash-free) لكتابة الـ Unit Tests في test/unit/ مجاناً وشغل flutter test.
3. المراجع المعماري (Argon / Opus): راجع فقط أسطر الـ git diff الصافية (+/-) التي تغيرت واعتمد التعديل.
4. أتمتة Notion: وثق النتيجة في ملف DELEG-FEAT داخل MADAR/delegation/، وحدث صفحة المهمة في Notion بقاعدة بيانات Tasks كـ Done.
```

---

## 5. خطوات دورة العمل التقنية الصارمة

1. **الفرز الأولي:** كتابة كود `lib/` بواسطة Gemini 3.8 Flash والتأكد من `flutter analyze`.
2. **التفويض للاختبارات:** اختيار الموديل المناسب من أسطول OpenCode وتشغيله عبر:
   ```powershell
   node ".agents/skills/opencode-delegate/scripts/relay.mjs" --brief brief-temp.txt --model opencode/<chosen-free-model> --pure --cd "G:\development\POS-Offline-Desktop-main" --timeout 5m
   ```
3. **فحص الـ Delta فقط:** استخراج `git diff -U2 lib/` وعرضه فقط على Argon لاعتماده.
4. **المزامنة مع Notion:** تشغيل المزامنة التلقائية مع Notion عبر السكريبت المعتمد أو أدوات Notion MCP المدمجة:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "C:\Users\Momen\.gemini\config\scripts\sync_bug_to_github_and_notion.ps1" -File "MADAR/delegation/DELEG-FEAT-<number>-<slug>.md"
   ```
