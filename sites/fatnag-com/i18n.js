(() => {
  /** Top 10 languages by global reach, aligned with fatnag AppLanguage codes. */
  const LANGS = [
    { code: "en", label: "English", dir: "ltr" },
    { code: "zh-Hans", label: "简体中文", dir: "ltr" },
    { code: "es", label: "Español", dir: "ltr" },
    { code: "hi", label: "हिन्दी", dir: "ltr" },
    { code: "ar", label: "العربية", dir: "rtl" },
    { code: "pt-BR", label: "Português", dir: "ltr" },
    { code: "ja", label: "日本語", dir: "ltr" },
    { code: "fr", label: "Français", dir: "ltr" },
    { code: "de", label: "Deutsch", dir: "ltr" },
    { code: "ko", label: "한국어", dir: "ltr" },
  ];

  const STORAGE_KEY = "fatnag.lang";

  /** Country (ISO 3166-1 alpha-2) → language code. */
  const COUNTRY_LANG = {
    US: "en", GB: "en", AU: "en", NZ: "en", IE: "en",
    CA: "en", SG: "en", PH: "en", IN: "hi",
    CN: "zh-Hans",
    ES: "es", MX: "es", AR: "es", CO: "es", CL: "es", PE: "es",
    VE: "es", EC: "es", GT: "es", CU: "es", BO: "es", DO: "es",
    HN: "es", PY: "es", SV: "es", NI: "es", CR: "es", PA: "es", UY: "es",
    SA: "ar", AE: "ar", EG: "ar", MA: "ar", DZ: "ar", IQ: "ar",
    JO: "ar", KW: "ar", QA: "ar", BH: "ar", OM: "ar", LB: "ar", TN: "ar",
    BR: "pt-BR", PT: "pt-BR", AO: "pt-BR", MZ: "pt-BR",
    JP: "ja",
    FR: "fr", BE: "fr", LU: "fr", MC: "fr",
    DE: "de", AT: "de", LI: "de",
    KR: "ko",
    CH: "de", // default; browser lang can override to fr/it
  };

  const STRINGS = {
    en: {
      "meta.title": "fatnag - Nag until the fat folds",
      "meta.description": "Privacy-first weigh-in companion. Daily weigh-ins, honest weekly goals, optional Keel coach. Nag until the fat folds.",
      "nav.how": "How it works",
      "nav.keel": "Keel",
      "nav.privacy": "Privacy",
      "nav.support": "Support",
      "nav.get": "Get the app",
      "nav.lang": "Language",
      "hero.h1": "Nag until the fat folds.",
      "hero.lead": "Daily weigh-ins that keep the routine until the loss shows. Honest numbers. Optional Keel when you go soft.",
      "hero.download": "Download on the App Store",
      "hero.see": "See the product",
      "hero.meta.bt": "Bluetooth scale auto-detect",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Works with",
      "works.bt": "Bluetooth scales (auto-detect)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "On-device Apple Intelligence",
      "how.kicker": "The loop",
      "how.title": "One job. The goal you set.",
      "how.lead": "Done pretending it fixes itself. Weigh, stay honest, win the week - or get offended. That is the point.",
      "how.f1.title": "Step on. Confirm. Move on.",
      "how.f1.body": "Step on a Bluetooth-compatible scale. fatnag auto-detects it, settles the reading, writes to Apple Health. Manual entry when the scale is elsewhere.",
      "how.f1.p1": "Auto-detects Bluetooth-compatible scales nearby",
      "how.f1.p2": "Body fat when impedance lands",
      "how.f1.p3": "Same-time weigh habit beats heroics",
      "how.f2.title": "Win the week, not the hour.",
      "how.f2.body": "Horizon arc, daily energy / protein / steps, and a today-ahead line that tells you what actually matters before Sunday.",
      "how.f2.p1": "Aggressive weekly catch-up when you fall behind",
      "how.f2.p2": "Red card when a spike looks like noise or sabotage",
      "how.f2.p3": "Progress charts with ideal line - no dashboard soup",
      "keel.kicker": "Keel coach",
      "keel.title": "Live pressure. Weekly credits.",
      "keel.body": "Keel is the only voice you talk to - blunt, local-language humour, no multi-agent dump. Free / Plus / Pro caps keep chat from becoming a coping hobby.",
      "keel.aside": "On-device polish when Apple Intelligence is around. Optional Grok when you consent. Never a medical device.",
      "keel.quote1": "Lie to yourself and you get offended.",
      "keel.quote2": "Good. That is the point.",
      "shots.kicker": "Product",
      "shots.title": "The app, not the pitch deck.",
      "shots.lead": "Screenshot slots for App Store art. Drop PNG/WebP into /assets/shots/ when ready.",
      "privacy.kicker": "Privacy",
      "privacy.title": "Most of it never leaves the phone.",
      "privacy.body": "Weigh-ins, profile, charts, and local coaching stay on-device. Keel only gets what you consent to send. We do not sell your data. No ad networks.",
      "privacy.policy": "Privacy Policy",
      "privacy.terms": "Terms",
      "cta.kicker": "Ready",
      "cta.title": "Go weigh yourself. Now.",
      "cta.lead": "Honest coach. Real numbers. Daily nag until the pants fit.",
      "cta.download": "Download on the App Store",
      "cta.support": "Need support?",
      "footer.tag": "Nag until the fat folds. Human Analog Limited. Not a medical device.",
      "footer.product": "Product",
      "footer.support": "Support",
      "footer.legal": "Legal",
      "footer.how": "How it works",
      "footer.keel": "Keel",
      "footer.download": "Download",
      "footer.help": "Help",
      "footer.contact": "Contact",
      "footer.privacy": "Privacy",
      "footer.terms": "Terms",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    "zh-Hans": {
      "meta.title": "fatnag - 催到脂肪服软",
      "meta.description": "称重数据尽量留在手机上。每天称、诚实的周目标、可选 Keel 教练。催到脂肪服软。",
      "nav.how": "怎么用",
      "nav.keel": "Keel",
      "nav.privacy": "隐私",
      "nav.support": "支持",
      "nav.get": "获取应用",
      "nav.lang": "语言",
      "hero.h1": "催到脂肪服软。",
      "hero.lead": "每天称。习惯撑到肉眼看得见。数字不骗人。你一松懈，就有 Keel。",
      "hero.download": "在 App Store 下载",
      "hero.see": "看看产品",
      "hero.meta.bt": "蓝牙秤自动识别",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "兼容",
      "works.bt": "蓝牙体脂秤（自动识别）",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence，本机运行",
      "how.kicker": "闭环",
      "how.title": "一件事。你定的目标。",
      "how.lead": "别再指望自己会好起来。你称、你诚实、你赢这一周。不然就刺痛。故意的。",
      "how.f1.title": "上秤。确认。走人。",
      "how.f1.body": "站上兼容的蓝牙秤。fatnag 自动识别，锁定读数，写入 Apple Health。没秤就手输。",
      "how.f1.p1": "自动识别身边的兼容蓝牙秤",
      "how.f1.p2": "阻抗一到就出体脂",
      "how.f1.p3": "每天同一时间称，胜过偶尔拼命",
      "how.f2.title": "赢的是一周，不是一小时。",
      "how.f2.body": "进度曲线，今日能量 / 蛋白 / 步数，还有一条「今天」线，告诉你周日之前什么真要紧。",
      "how.f2.p1": "一落后就激进追赶本周",
      "how.f2.p2": "尖峰像噪声或自毁就亮红牌",
      "how.f2.p3": "进度图加理想线。没有臃肿仪表盘。",
      "keel.kicker": "Keel 教练",
      "keel.title": "实时施压。每周额度。",
      "keel.body": "Keel 是唯一的声音。直球，用你的语言开玩笑，不是一堆智能体开会。Free / Plus / Pro 上限，别把聊天当成逃避正事的爱好。",
      "keel.aside": "有 Apple Intelligence 就在本机润色。可选 Grok，只有你同意才开。不是医疗器械。",
      "keel.quote1": "骗自己，就会心烦。",
      "keel.quote2": "很好。故意的。",
      "shots.kicker": "产品",
      "shots.title": "是应用。不是推销稿。",
      "shots.lead": "App Store 截图位。准备好后把 PNG/WebP 放进 /assets/shots/。",
      "privacy.kicker": "隐私",
      "privacy.title": "几乎没什么会离开手机。",
      "privacy.body": "称重、资料、曲线和本机教练都在设备上。Keel 只拿你同意发送的。我们不卖数据。没有广告网络。",
      "privacy.policy": "隐私政策",
      "privacy.terms": "条款",
      "cta.kicker": "准备好了",
      "cta.title": "现在就去称体重。",
      "cta.lead": "诚实教练。真实数字。每天催，直到裤子合身。",
      "cta.download": "在 App Store 下载",
      "cta.support": "需要支持？",
      "footer.tag": "催到脂肪服软。Human Analog Limited。非医疗器械。",
      "footer.product": "产品",
      "footer.support": "支持",
      "footer.legal": "法律",
      "footer.how": "怎么用",
      "footer.keel": "Keel",
      "footer.download": "下载",
      "footer.help": "帮助",
      "footer.contact": "联系",
      "footer.privacy": "隐私",
      "footer.terms": "条款",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    es: {
      "meta.title": "fatnag - Insiste hasta que la grasa ceda",
      "meta.description": "Compañero de peso que se queda en tu teléfono. Pesajes diarios, metas semanales honestas, coach Keel opcional. Insiste hasta que la grasa ceda.",
      "nav.how": "Cómo funciona",
      "nav.keel": "Keel",
      "nav.privacy": "Privacidad",
      "nav.support": "Soporte",
      "nav.get": "Obtener la app",
      "nav.lang": "Idioma",
      "hero.h1": "Insiste hasta que la grasa ceda.",
      "hero.lead": "Pésate todos los días. La rutina aguanta hasta que se note. Números de verdad. Keel opcional en cuanto aflojas.",
      "hero.download": "Descargar en el App Store",
      "hero.see": "Ver el producto",
      "hero.meta.bt": "Báscula Bluetooth detección auto",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Compatible con",
      "works.bt": "Básculas Bluetooth (detección auto)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence, en el dispositivo",
      "how.kicker": "El ciclo",
      "how.title": "Un solo trabajo. La meta que fijaste.",
      "how.lead": "Basta de creer que se arregla solo. Te pesas, te mantienes honesto, ganas la semana. Si no, pica. A propósito.",
      "how.f1.title": "Súbete a la báscula. Valida. Sigue.",
      "how.f1.body": "Te subes a una báscula Bluetooth compatible. fatnag la detecta, fija la medida, la escribe en Apple Health. Entrada manual si no hay báscula.",
      "how.f1.p1": "Detecta básculas Bluetooth compatibles a tu alrededor",
      "how.f1.p2": "Grasa corporal en cuanto llega la impedancia",
      "how.f1.p3": "Pesarse a la misma hora gana a los gestos heroicos",
      "how.f2.title": "Gana la semana, no la hora.",
      "how.f2.body": "Curva de horizonte, energía / proteína / pasos del día, y una línea de «hoy» que te dice qué importa de verdad antes del domingo.",
      "how.f2.p1": "Alcance semanal agresivo en cuanto te atrasas",
      "how.f2.p2": "Tarjeta roja si un pico parece ruido o sabotaje",
      "how.f2.p3": "Gráficas con línea ideal. Sin panel de control indigesto.",
      "keel.kicker": "Coach Keel",
      "keel.title": "Presión en directo. Créditos cada semana.",
      "keel.body": "Keel es la única voz. Directa, humor en tu idioma, no un comité de agentes. Los topes Free / Plus / Pro impiden que el chat se vuelva un hobby para evitar el tema.",
      "keel.aside": "Acabado en el dispositivo con Apple Intelligence. Grok opcional, solo si aceptas. No es un dispositivo médico.",
      "keel.quote1": "Te mientes y te molesta.",
      "keel.quote2": "Bien. A propósito.",
      "shots.kicker": "Producto",
      "shots.title": "La app. No el pitch.",
      "shots.lead": "Espacios para capturas del App Store. Deja PNG/WebP en /assets/shots/ cuando estén listas.",
      "privacy.kicker": "Privacidad",
      "privacy.title": "Casi nada sale del teléfono.",
      "privacy.body": "Pesajes, perfil, curvas y coaching local quedan en el dispositivo. Keel solo recibe lo que aceptas enviar. No vendemos tus datos. Sin redes publicitarias.",
      "privacy.policy": "Política de privacidad",
      "privacy.terms": "Términos",
      "cta.kicker": "Listo",
      "cta.title": "Ve a pesarte. Ahora.",
      "cta.lead": "Coach honesto. Números reales. Insiste cada día hasta que cierre el pantalón.",
      "cta.download": "Descargar en el App Store",
      "cta.support": "¿Necesitas soporte?",
      "footer.tag": "Insiste hasta que la grasa ceda. Human Analog Limited. No es un dispositivo médico.",
      "footer.product": "Producto",
      "footer.support": "Soporte",
      "footer.legal": "Legal",
      "footer.how": "Cómo funciona",
      "footer.keel": "Keel",
      "footer.download": "Descargar",
      "footer.help": "Ayuda",
      "footer.contact": "Contacto",
      "footer.privacy": "Privacidad",
      "footer.terms": "Términos",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    hi: {
      "meta.title": "fatnag - चर्बी हारे तक रटो",
      "meta.description": "वज़न का साथी जो फ़ोन पर रहता है। रोज़ तौल, ईमानदार साप्ताहिक लक्ष्य, वैकल्पिक Keel कोच। चर्बी हारे तक रटो।",
      "nav.how": "कैसे काम करता है",
      "nav.keel": "Keel",
      "nav.privacy": "गोपनीयता",
      "nav.support": "सहायता",
      "nav.get": "ऐप लें",
      "nav.lang": "भाषा",
      "hero.h1": "चर्बी हारे तक रटो।",
      "hero.lead": "रोज़ तौल। आदत तब तक चलती है जब तक नतीजा दिखे। असली आँकड़े। ढीले पड़े तो Keel।",
      "hero.download": "App Store पर डाउनलोड करें",
      "hero.see": "प्रोडक्ट देखें",
      "hero.meta.bt": "ब्लूटूथ तराज़ू अपने आप पहचानी",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "इनके साथ चलता है",
      "works.bt": "ब्लूटूथ तराज़ू (अपने आप पहचान)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence, डिवाइस पर",
      "how.kicker": "चक्र",
      "how.title": "एक काम। जो लक्ष्य तुमने रखा।",
      "how.lead": "ये ख़याल छोड़ो कि खुद ठीक हो जाएगा। तौल, ईमानदार रह, हफ़्ता जीत। नहीं तो चुभे। जान-बूझकर।",
      "how.f1.title": "तराज़ू पर खड़े हो। पक्का करो। आगे बढ़ो।",
      "how.f1.body": "संगत ब्लूटूथ तराज़ू पर खड़े हो। fatnag उसे पहचानती है, माप तय करती है, Apple Health में लिखती है। तराज़ू न हो तो हाथ से डालो।",
      "how.f1.p1": "पास की संगत ब्लूटूथ तराज़ू अपने आप पहचानती है",
      "how.f1.p2": "प्रतिबाधा आते ही बॉडी फ़ैट",
      "how.f1.p3": "एक ही वक्त तौलना, दिखावे वाली मेहनत से बेहतर",
      "how.f2.title": "घंटा नहीं, हफ़्ता जीतो।",
      "how.f2.body": "प्रगति की रेखा, आज की ऊर्जा / प्रोटीन / कदम, और एक «आज» वाली लाइन जो रविवार से पहले असल बात बताए।",
      "how.f2.p1": "पीछे रहो तो हफ़्ते का आक्रामक रफ़ू",
      "how.f2.p2": "शिखर शोर या तोड़फोड़ लगे तो लाल कार्ड",
      "how.f2.p3": "आदर्श रेखा वाले चार्ट। कोई उलझा पैनल नहीं।",
      "keel.kicker": "Keel कोच",
      "keel.title": "लाइव दबाव। हर हफ़्ते क्रेडिट।",
      "keel.body": "Keel एक ही आवाज़ है। सीधी, तुम्हारी भाषा में मज़ाक, एजेंटों की कमिटी नहीं। Free / Plus / Pro की सीमा ताकि चैट मुद्दे से भागने का शौक न बने।",
      "keel.aside": "Apple Intelligence हो तो डिवाइस पर फिनिश। Grok वैकल्पिक, सिर्फ़ तुम्हारी मंज़ूरी पर। मेडिकल डिवाइस नहीं।",
      "keel.quote1": "खुद से झूठ बोलोगे तो खिझाओगे।",
      "keel.quote2": "ठीक है। जान-बूझकर।",
      "shots.kicker": "प्रोडक्ट",
      "shots.title": "ऐप। पिच नहीं।",
      "shots.lead": "App Store स्क्रीनशॉट के स्लॉट। तैयार होने पर PNG/WebP /assets/shots/ में डालो।",
      "privacy.kicker": "गोपनीयता",
      "privacy.title": "लगभग कुछ भी फ़ोन से बाहर नहीं जाता।",
      "privacy.body": "तौल, प्रोफ़ाइल, कर्व और लोकल कोचिंग डिवाइस पर रहती है। Keel सिर्फ़ वो लेता है जो तुम भेजने को मानो। हम डेटा नहीं बेचते। कोई विज्ञापन नेटवर्क नहीं।",
      "privacy.policy": "गोपनीयता नीति",
      "privacy.terms": "नियम",
      "cta.kicker": "तैयार",
      "cta.title": "अभी तौलने जाओ।",
      "cta.lead": "ईमानदार कोच। असली आँकड़े। पैंट फिट होने तक रोज़ रटो।",
      "cta.download": "App Store पर डाउनलोड करें",
      "cta.support": "सहायता चाहिए?",
      "footer.tag": "चर्बी हारे तक रटो। Human Analog Limited। मेडिकल डिवाइस नहीं।",
      "footer.product": "प्रोडक्ट",
      "footer.support": "सहायता",
      "footer.legal": "कानूनी",
      "footer.how": "कैसे काम करता है",
      "footer.keel": "Keel",
      "footer.download": "डाउनलोड",
      "footer.help": "मदद",
      "footer.contact": "संपर्क",
      "footer.privacy": "गोपनीयता",
      "footer.terms": "नियम",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    ar: {
      "meta.title": "fatnag - يلحّ حتى تستسلم الدهون",
      "meta.description": "رفيق وزن يبقى على هاتفك. وزن يومي، أهداف أسبوعية صادقة، ومدرب Keel اختياري. يلحّ حتى تستسلم الدهون.",
      "nav.how": "كيف يعمل",
      "nav.keel": "Keel",
      "nav.privacy": "الخصوصية",
      "nav.support": "الدعم",
      "nav.get": "احصل على التطبيق",
      "nav.lang": "اللغة",
      "hero.h1": "يلحّ حتى تستسلم الدهون.",
      "hero.lead": "زِن كل يوم. الروتين يصمد حتى يظهر الفرق. أرقام حقيقية. Keel اختياري حين تتهاون.",
      "hero.download": "حمّل من App Store",
      "hero.see": "شاهد المنتج",
      "hero.meta.bt": "ميزان بلوتوث يُكتشف تلقائياً",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "+18",
      "works.title": "يعمل مع",
      "works.bt": "موازين بلوتوث (كشف تلقائي)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence، على الجهاز",
      "how.kicker": "الحلقة",
      "how.title": "مهمة واحدة. الهدف الذي حددته.",
      "how.lead": "كفى اعتقاداً أنه سيصلح نفسه. تزن، تبقى صادقاً، تربح الأسبوع. وإلا يوخز. هذا مقصود.",
      "how.f1.title": "اصعد على الميزان. أكّد. انتقل.",
      "how.f1.body": "تصعد على ميزان بلوتوث متوافق. fatnag يكتشفه، يثبّت القياس، ويكتبه في Apple Health. إدخال يدوي إن لم يتوفر الميزان.",
      "how.f1.p1": "يكتشف موازين البلوتوث المتوافقة من حولك",
      "how.f1.p2": "دهون الجسم فور وصول الممانعة",
      "how.f1.p3": "الوزن في وقت ثابت يتفوق على البطولات المؤقتة",
      "how.f2.title": "اربح الأسبوع لا الساعة.",
      "how.f2.body": "منحنى الأفق، طاقة / بروتين / خطوات اليوم، وخط «اليوم» يوضح ما يهم حقاً قبل الأحد.",
      "how.f2.p1": "لحاق أسبوعي حاد فور التأخر",
      "how.f2.p2": "بطاقة حمراء إن بدا الارتفاع ضجيجاً أو تخريباً",
      "how.f2.p3": "رسوم مع خط مثالي. بلا لوحة تحكم مزدحمة.",
      "keel.kicker": "مدرب Keel",
      "keel.title": "ضغط مباشر. أرصدة كل أسبوع.",
      "keel.body": "Keel هو الصوت الوحيد. مباشر، فكاهة بلغتك، لا لجنة وكلاء. حدود Free / Plus / Pro تمنع أن تصبح الدردشة هواية للهروب من الموضوع.",
      "keel.aside": "لمسة أخيرة على الجهاز مع Apple Intelligence. Grok اختياري، فقط إذا وافقت. ليس جهازاً طبياً.",
      "keel.quote1": "تكذب على نفسك فتتضايق.",
      "keel.quote2": "حسناً. هذا مقصود.",
      "shots.kicker": "المنتج",
      "shots.title": "التطبيق. ليس العرض.",
      "shots.lead": "أماكن لقطات App Store. ضع PNG/WebP في /assets/shots/ عند الجاهزية.",
      "privacy.kicker": "الخصوصية",
      "privacy.title": "لا يكاد شيء يغادر الهاتف.",
      "privacy.body": "الأوزان والملف والمنحنيات والتدريب المحلي تبقى على الجهاز. Keel يأخذ فقط ما توافق على إرساله. لا نبيع بياناتك. بلا شبكات إعلانات.",
      "privacy.policy": "سياسة الخصوصية",
      "privacy.terms": "الشروط",
      "cta.kicker": "جاهز",
      "cta.title": "اذهب زن نفسك. الآن.",
      "cta.lead": "مدرب صادق. أرقام حقيقية. إلحاح يومي حتى يلائم البنطلون.",
      "cta.download": "حمّل من App Store",
      "cta.support": "تحتاج دعماً؟",
      "footer.tag": "يلحّ حتى تستسلم الدهون. Human Analog Limited. ليس جهازاً طبياً.",
      "footer.product": "المنتج",
      "footer.support": "الدعم",
      "footer.legal": "قانوني",
      "footer.how": "كيف يعمل",
      "footer.keel": "Keel",
      "footer.download": "تحميل",
      "footer.help": "مساعدة",
      "footer.contact": "تواصل",
      "footer.privacy": "الخصوصية",
      "footer.terms": "الشروط",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    "pt-BR": {
      "meta.title": "fatnag - Insiste até a gordura ceder",
      "meta.description": "Companheiro de peso que fica no seu telefone. Pesagens diárias, metas semanais honestas, coach Keel opcional. Insiste até a gordura ceder.",
      "nav.how": "Como funciona",
      "nav.keel": "Keel",
      "nav.privacy": "Privacidade",
      "nav.support": "Suporte",
      "nav.get": "Baixar o app",
      "nav.lang": "Idioma",
      "hero.h1": "Insiste até a gordura ceder.",
      "hero.lead": "Pese todo dia. A rotina segura até dar pra ver. Números de verdade. Keel opcional assim que você afrouxa.",
      "hero.download": "Baixar na App Store",
      "hero.see": "Ver o produto",
      "hero.meta.bt": "Balança Bluetooth com detecção auto",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Funciona com",
      "works.bt": "Balanças Bluetooth (detecção auto)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence, no aparelho",
      "how.kicker": "O ciclo",
      "how.title": "Um trabalho. A meta que você definiu.",
      "how.lead": "Chega de achar que se resolve sozinho. Você se pesa, fica honesto, ganha a semana. Senão dói. De propósito.",
      "how.f1.title": "Sobe na balança. Confirma. Segue.",
      "how.f1.body": "Você sobe numa balança Bluetooth compatível. fatnag detecta, trava a medida, grava no Apple Health. Entrada manual se não tiver balança.",
      "how.f1.p1": "Detecta balanças Bluetooth compatíveis por perto",
      "how.f1.p2": "Gordura corporal assim que a impedância chega",
      "how.f1.p3": "Pesar no mesmo horário vence o heroísmo de uma vez",
      "how.f2.title": "Vença a semana, não a hora.",
      "how.f2.body": "Curva de horizonte, energia / proteína / passos do dia, e uma linha de «hoje» que diz o que importa de verdade antes do domingo.",
      "how.f2.p1": "Recuperação semanal agressiva assim que você atrasa",
      "how.f2.p2": "Cartão vermelho se um pico parecer ruído ou sabotagem",
      "how.f2.p3": "Gráficos com linha ideal. Sem painel indigesto.",
      "keel.kicker": "Coach Keel",
      "keel.title": "Pressão ao vivo. Créditos toda semana.",
      "keel.body": "Keel é a única voz. Direta, humor no seu idioma, sem comitê de agentes. Limites Free / Plus / Pro impedem o chat de virar hobby pra fugir do assunto.",
      "keel.aside": "Acabamento no aparelho com Apple Intelligence. Grok opcional, só se você aceitar. Não é dispositivo médico.",
      "keel.quote1": "Você se mente e se irrita.",
      "keel.quote2": "Bom. De propósito.",
      "shots.kicker": "Produto",
      "shots.title": "O app. Não o pitch.",
      "shots.lead": "Espaços para prints da App Store. Coloque PNG/WebP em /assets/shots/ quando estiver pronto.",
      "privacy.kicker": "Privacidade",
      "privacy.title": "Quase nada sai do telefone.",
      "privacy.body": "Pesagens, perfil, curvas e coaching local ficam no aparelho. Keel só recebe o que você aceita enviar. Não vendemos seus dados. Sem redes de anúncio.",
      "privacy.policy": "Política de privacidade",
      "privacy.terms": "Termos",
      "cta.kicker": "Pronto",
      "cta.title": "Vá se pesar. Agora.",
      "cta.lead": "Coach honesto. Números de verdade. Insiste todo dia até a calça fechar.",
      "cta.download": "Baixar na App Store",
      "cta.support": "Precisa de suporte?",
      "footer.tag": "Insiste até a gordura ceder. Human Analog Limited. Não é dispositivo médico.",
      "footer.product": "Produto",
      "footer.support": "Suporte",
      "footer.legal": "Legal",
      "footer.how": "Como funciona",
      "footer.keel": "Keel",
      "footer.download": "Baixar",
      "footer.help": "Ajuda",
      "footer.contact": "Contato",
      "footer.privacy": "Privacidade",
      "footer.terms": "Termos",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    ja: {
      "meta.title": "fatnag - 脂肪が負けるまで食い下がる",
      "meta.description": "データは端末に残す体重コンパニオン。毎日の計測、正直な週間目標、任意の Keel コーチ。脂肪が負けるまで食い下がる。",
      "nav.how": "仕組み",
      "nav.keel": "Keel",
      "nav.privacy": "プライバシー",
      "nav.support": "サポート",
      "nav.get": "アプリを入手",
      "nav.lang": "言語",
      "hero.h1": "脂肪が負けるまで食い下がる。",
      "hero.lead": "毎日測る。結果が見えるまでルーティンを続ける。本物の数字。緩んだら Keel。",
      "hero.download": "App Store でダウンロード",
      "hero.see": "プロダクトを見る",
      "hero.meta.bt": "Bluetooth 体重計を自動検出",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "対応",
      "works.bt": "Bluetooth 体組成計（自動検出）",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence、端末内",
      "how.kicker": "ループ",
      "how.title": "仕事は一つ。あなたが決めた目標。",
      "how.lead": "勝手に治ると信じるのは終わり。測る、正直でいる、週を勝つ。嫌なら嫌でいい。それが狙いだ。",
      "how.f1.title": "体重計に乗る。確定。次へ。",
      "how.f1.body": "対応 Bluetooth スケールに乗る。fatnag が検出し、測定を確定して Apple Health に書く。スケールがなければ手動入力。",
      "how.f1.p1": "近くの対応 Bluetooth スケールを自動検出",
      "how.f1.p2": "インピーダンスが来たら体脂肪",
      "how.f1.p3": "同じ時間に測る習慣が、一度きりの気合に勝つ",
      "how.f2.title": "勝つのは週。時間ではない。",
      "how.f2.body": "進捗カーブ、今日のエネルギー / たんぱく / 歩数、日曜までに本当に重要な「今日」のライン。",
      "how.f2.p1": "遅れたら攻撃的に週を取り戻す",
      "how.f2.p2": "スパイクがノイズやサボタージュならレッドカード",
      "how.f2.p3": "理想線つきのグラフ。見づらいダッシュボードはやらない。",
      "keel.kicker": "Keel コーチ",
      "keel.title": "ライブの圧力。毎週クレジット。",
      "keel.body": "Keel は唯一の声。率直、あなたの言語のユーモア、エージェント委員会なし。Free / Plus / Pro 上限で、チャットを話題逃れの趣味にしない。",
      "keel.aside": "Apple Intelligence があれば端末内で仕上げ。Grok は同意したときだけ。医療機器ではない。",
      "keel.quote1": "自分に嘘をつくとムカつく。",
      "keel.quote2": "いい。それが狙いだ。",
      "shots.kicker": "プロダクト",
      "shots.title": "アプリ。ピッチじゃない。",
      "shots.lead": "App Store 用スクショ枠。準備できたら PNG/WebP を /assets/shots/ へ。",
      "privacy.kicker": "プライバシー",
      "privacy.title": "ほとんど何も端末から出ない。",
      "privacy.body": "計測、プロフィール、カーブ、ローカルコーチングは端末内。Keel は同意した分だけ。データは売らない。広告ネットワークなし。",
      "privacy.policy": "プライバシーポリシー",
      "privacy.terms": "利用規約",
      "cta.kicker": "準備はいいか",
      "cta.title": "今すぐ体重を測れ。",
      "cta.lead": "正直なコーチ。本物の数字。ズボンが合うまで毎日食い下がる。",
      "cta.download": "App Store でダウンロード",
      "cta.support": "サポートが必要？",
      "footer.tag": "脂肪が負けるまで食い下がる。Human Analog Limited。医療機器ではない。",
      "footer.product": "プロダクト",
      "footer.support": "サポート",
      "footer.legal": "法的情報",
      "footer.how": "仕組み",
      "footer.keel": "Keel",
      "footer.download": "ダウンロード",
      "footer.help": "ヘルプ",
      "footer.contact": "連絡",
      "footer.privacy": "プライバシー",
      "footer.terms": "利用規約",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    fr: {
      "meta.title": "fatnag - Relance jusqu'à ce que le gras cède",
      "meta.description": "Compagnon de pesée qui reste sur ton téléphone. Pesées tous les jours, objectifs hebdo honnêtes, coach Keel en option. Relance jusqu'à ce que le gras cède.",
      "nav.how": "Comment ça marche",
      "nav.keel": "Keel",
      "nav.privacy": "Confidentialité",
      "nav.support": "Support",
      "nav.get": "Obtenir l'app",
      "nav.lang": "Langue",
      "hero.h1": "Relance jusqu'à ce que le gras cède.",
      "hero.lead": "Pesée tous les jours. La routine tient jusqu'à ce que ça se voie. Des vrais chiffres. Keel en option dès que tu flanches.",
      "hero.download": "Télécharger sur l'App Store",
      "hero.see": "Voir le produit",
      "hero.meta.bt": "Balance Bluetooth détectée auto",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Compatible avec",
      "works.bt": "Balances Bluetooth (détection auto)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence, en local",
      "how.kicker": "La boucle",
      "how.title": "Un seul job. L'objectif que tu as fixé.",
      "how.lead": "Fini de croire que ça va se régler tout seul. Tu te pèses, tu restes honnête, tu gagnes la semaine. Sinon ça pique. C'est voulu.",
      "how.f1.title": "Monte sur la balance. Valide. Passe à autre chose.",
      "how.f1.body": "Tu montes sur une balance Bluetooth compatible. fatnag la détecte, fige la mesure, l'écrit dans Apple Health. Saisie manuelle si la balance n'est pas là.",
      "how.f1.p1": "Détecte les balances Bluetooth compatibles autour de toi",
      "how.f1.p2": "Masse grasse dès que l'impédance tombe",
      "how.f1.p3": "Se peser à la même heure bat les coups d'éclat",
      "how.f2.title": "Gagne la semaine, pas l'heure.",
      "how.f2.body": "Courbe d'horizon, énergie / protéines / pas du jour, et une ligne « aujourd'hui » qui te dit ce qui compte vraiment avant dimanche.",
      "how.f2.p1": "Rattrapage hebdo agressif dès que tu prends du retard",
      "how.f2.p2": "Carton rouge si un pic ressemble à du bruit ou à du sabotage",
      "how.f2.p3": "Courbes avec ligne idéale. Pas un tableau de bord indigeste.",
      "keel.kicker": "Coach Keel",
      "keel.title": "Pression en direct. Crédits chaque semaine.",
      "keel.body": "Keel est la seule voix. Cash, humour dans ta langue, pas un comité d'agents. Les plafonds Free / Plus / Pro empêchent le chat de devenir un hobby pour éviter le sujet.",
      "keel.aside": "Finition en local avec Apple Intelligence. Grok en option, seulement si tu acceptes. Pas un dispositif médical.",
      "keel.quote1": "Tu te mens, ça te vexe.",
      "keel.quote2": "Bien. C'est voulu.",
      "shots.kicker": "Produit",
      "shots.title": "L'app. Pas le pitch.",
      "shots.lead": "Emplacements pour captures App Store. Dépose PNG/WebP dans /assets/shots/ quand c'est prêt.",
      "privacy.kicker": "Confidentialité",
      "privacy.title": "Presque rien ne quitte le téléphone.",
      "privacy.body": "Pesées, profil, courbes et coaching local restent sur l'appareil. Keel ne reçoit que ce que tu acceptes d'envoyer. On ne vend pas tes données. Pas de réseaux pub.",
      "privacy.policy": "Politique de confidentialité",
      "privacy.terms": "Conditions",
      "cta.kicker": "Prêt",
      "cta.title": "Va te peser. Maintenant.",
      "cta.lead": "Coach honnête. Vrais chiffres. Relance tous les jours jusqu'à ce que le pantalon passe.",
      "cta.download": "Télécharger sur l'App Store",
      "cta.support": "Besoin d'aide ?",
      "footer.tag": "Relance jusqu'à ce que le gras cède. Human Analog Limited. Pas un dispositif médical.",
      "footer.product": "Produit",
      "footer.support": "Support",
      "footer.legal": "Légal",
      "footer.how": "Comment ça marche",
      "footer.keel": "Keel",
      "footer.download": "Télécharger",
      "footer.help": "Aide",
      "footer.contact": "Contact",
      "footer.privacy": "Confidentialité",
      "footer.terms": "Conditions",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    de: {
      "meta.title": "fatnag - Nachhaken, bis das Fett nachgibt",
      "meta.description": "Wiege-Begleiter, der auf dem Telefon bleibt. Tägliches Wiegen, ehrliche Wochenziele, optionaler Keel-Coach. Nachhaken, bis das Fett nachgibt.",
      "nav.how": "So geht's",
      "nav.keel": "Keel",
      "nav.privacy": "Datenschutz",
      "nav.support": "Support",
      "nav.get": "App holen",
      "nav.lang": "Sprache",
      "hero.h1": "Nachhaken, bis das Fett nachgibt.",
      "hero.lead": "Jeden Tag wiegen. Die Routine hält, bis man's sieht. Echte Zahlen. Optional Keel, sobald du weich wirst.",
      "hero.download": "Im App Store laden",
      "hero.see": "Produkt ansehen",
      "hero.meta.bt": "Bluetooth-Waage mit Auto-Erkennung",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Funktioniert mit",
      "works.bt": "Bluetooth-Waagen (Auto-Erkennung)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence, auf dem Gerät",
      "how.kicker": "Die Schleife",
      "how.title": "Ein Job. Das Ziel, das du gesetzt hast.",
      "how.lead": "Hör auf zu glauben, es richtet sich von selbst. Du wiegst dich, bleibst ehrlich, gewinnst die Woche. Sonst piekt's. Absicht.",
      "how.f1.title": "Auf die Waage. Bestätigen. Weiter.",
      "how.f1.body": "Du steigst auf eine Bluetooth-kompatible Waage. fatnag erkennt sie, hält den Wert fest, schreibt in Apple Health. Manuell, wenn keine Waage da ist.",
      "how.f1.p1": "Erkennt Bluetooth-kompatible Waagen in der Nähe",
      "how.f1.p2": "Körperfett, sobald Impedanz da ist",
      "how.f1.p3": "Zur gleichen Zeit wiegen schlägt einmalige Heldentaten",
      "how.f2.title": "Gewinne die Woche, nicht die Stunde.",
      "how.f2.body": "Horizontkurve, Energie / Protein / Schritte des Tages und eine «Heute»-Linie, die sagt, was vor Sonntag wirklich zählt.",
      "how.f2.p1": "Aggressives Wochen-Aufholen, sobald du hinterherhinkst",
      "how.f2.p2": "Rote Karte, wenn ein Spike nach Rauschen oder Sabotage aussieht",
      "how.f2.p3": "Kurven mit Ideallinie. Kein überladenes Dashboard.",
      "keel.kicker": "Keel-Coach",
      "keel.title": "Live-Druck. Credits jede Woche.",
      "keel.body": "Keel ist die einzige Stimme. Direkt, Humor in deiner Sprache, kein Agenten-Komitee. Free / Plus / Pro Caps verhindern, dass Chat ein Hobby wird, um dem Thema auszuweichen.",
      "keel.aside": "Feinschliff auf dem Gerät mit Apple Intelligence. Optional Grok, nur wenn du zustimmst. Kein Medizinprodukt.",
      "keel.quote1": "Lüg dich an und du bist genervt.",
      "keel.quote2": "Gut. Absicht.",
      "shots.kicker": "Produkt",
      "shots.title": "Die App. Nicht der Pitch.",
      "shots.lead": "Screenshot-Slots für App-Store-Art. PNG/WebP nach /assets/shots/ legen, wenn bereit.",
      "privacy.kicker": "Datenschutz",
      "privacy.title": "Fast nichts verlässt das Telefon.",
      "privacy.body": "Wiegungen, Profil, Kurven und lokales Coaching bleiben auf dem Gerät. Keel bekommt nur, was du senden willst. Wir verkaufen deine Daten nicht. Keine Ad-Netzwerke.",
      "privacy.policy": "Datenschutzrichtlinie",
      "privacy.terms": "Bedingungen",
      "cta.kicker": "Bereit",
      "cta.title": "Geh dich wiegen. Jetzt.",
      "cta.lead": "Ehrlicher Coach. Echte Zahlen. Tägliches Nachhaken, bis die Hose sitzt.",
      "cta.download": "Im App Store laden",
      "cta.support": "Brauchst du Support?",
      "footer.tag": "Nachhaken, bis das Fett nachgibt. Human Analog Limited. Kein Medizinprodukt.",
      "footer.product": "Produkt",
      "footer.support": "Support",
      "footer.legal": "Rechtliches",
      "footer.how": "So geht's",
      "footer.keel": "Keel",
      "footer.download": "Laden",
      "footer.help": "Hilfe",
      "footer.contact": "Kontakt",
      "footer.privacy": "Datenschutz",
      "footer.terms": "Bedingungen",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    ko: {
      "meta.title": "fatnag - 지방이 항복할 때까지 잔소리",
      "meta.description": "데이터는 폰에 남는 체중 동반자. 매일 계측, 정직한 주간 목표, 선택형 Keel 코치. 지방이 항복할 때까지 잔소리.",
      "nav.how": "작동 방식",
      "nav.keel": "Keel",
      "nav.privacy": "개인정보",
      "nav.support": "지원",
      "nav.get": "앱 받기",
      "nav.lang": "언어",
      "hero.h1": "지방이 항복할 때까지 잔소리.",
      "hero.lead": "매일 재라. 결과가 보일 때까지 루틴을 유지한다. 진짜 숫자. 느슨해지면 Keel.",
      "hero.download": "App Store에서 다운로드",
      "hero.see": "제품 보기",
      "hero.meta.bt": "블루투스 체중계 자동 감지",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "연동",
      "works.bt": "블루투스 체중계 (자동 감지)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence, 기기에서",
      "how.kicker": "루프",
      "how.title": "할 일 하나. 당신이 정한 목표.",
      "how.lead": "알아서 고쳐질 거라는 생각은 그만. 재고, 정직하고, 이번 주를 이겨. 아니면 따갑다. 일부러.",
      "how.f1.title": "체중계에 올라서라. 확인. 다음.",
      "how.f1.body": "호환 블루투스 체중계에 올라선다. fatnag가 감지하고 측정을 고정한 뒤 Apple Health에 쓴다. 체중계가 없으면 수동 입력.",
      "how.f1.p1": "근처 호환 블루투스 체중계를 자동 감지",
      "how.f1.p2": "임피던스가 오면 체지방",
      "how.f1.p3": "같은 시간에 재는 습관이 한 번의 기합보다 낫다",
      "how.f2.title": "시간을 이기는 게 아니라 주를 이겨라.",
      "how.f2.body": "진행 곡선, 오늘 에너지 / 단백질 / 걸음, 일요일 전에 진짜 중요한 «오늘» 라인.",
      "how.f2.p1": "뒤처지면 공격적으로 주를 따라잡는다",
      "how.f2.p2": "스파이크가 노이즈나 사보타주면 레드 카드",
      "how.f2.p3": "이상선 있는 차트. 복잡한 대시보드 없음.",
      "keel.kicker": "Keel 코치",
      "keel.title": "실시간 압박. 매주 크레딧.",
      "keel.body": "Keel은 유일한 목소리. 직설, 당신 언어의 유머, 에이전트 위원회 없음. Free / Plus / Pro 한도로 채팅이 주제 회피 취미가 되지 않게.",
      "keel.aside": "Apple Intelligence가 있으면 기기에서 다듬기. Grok는 동의한 때만. 의료기기 아님.",
      "keel.quote1": "스스로에게 거짓말하면 기분이 상한다.",
      "keel.quote2": "좋다. 일부러.",
      "shots.kicker": "제품",
      "shots.title": "앱이다. 피치가 아니다.",
      "shots.lead": "App Store 스크린샷 슬롯. 준비되면 PNG/WebP를 /assets/shots/에.",
      "privacy.kicker": "개인정보",
      "privacy.title": "거의 아무것도 폰을 떠나지 않는다.",
      "privacy.body": "계측, 프로필, 곡선, 로컬 코칭은 기기에 남는다. Keel은 동의한 것만 받는다. 데이터를 팔지 않는다. 광고 네트워크 없음.",
      "privacy.policy": "개인정보 처리방침",
      "privacy.terms": "약관",
      "cta.kicker": "준비됐나",
      "cta.title": "지금 몸무게를 재라.",
      "cta.lead": "정직한 코치. 진짜 숫자. 바지가 맞을 때까지 매일 잔소리.",
      "cta.download": "App Store에서 다운로드",
      "cta.support": "지원이 필요하세요?",
      "footer.tag": "지방이 항복할 때까지 잔소리. Human Analog Limited. 의료기기 아님.",
      "footer.product": "제품",
      "footer.support": "지원",
      "footer.legal": "법적 고지",
      "footer.how": "작동 방식",
      "footer.keel": "Keel",
      "footer.download": "다운로드",
      "footer.help": "도움말",
      "footer.contact": "연락",
      "footer.privacy": "개인정보",
      "footer.terms": "약관",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
  };

  const byCode = Object.fromEntries(LANGS.map((l) => [l.code, l]));

  function normalize(code) {
    if (!code) return null;
    const raw = String(code).replace("_", "-");
    if (byCode[raw]) return raw;
    const lower = raw.toLowerCase();
    if (lower.startsWith("zh")) return "zh-Hans";
    if (lower.startsWith("pt")) return "pt-BR";
    const base = lower.split("-")[0];
    const hit = LANGS.find((l) => l.code.toLowerCase() === base || l.code.toLowerCase().startsWith(base + "-"));
    return hit ? hit.code : null;
  }

  function fromBrowser() {
    const list = [...(navigator.languages || []), navigator.language].filter(Boolean);
    for (const item of list) {
      const n = normalize(item);
      if (n) return n;
    }
    return null;
  }

  async function fromCountry() {
    try {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 1800);
      const res = await fetch("https://www.cloudflare.com/cdn-cgi/trace", {
        signal: ctrl.signal,
        cache: "no-store",
      });
      clearTimeout(t);
      const text = await res.text();
      const loc = (text.match(/^loc=([A-Z]{2})$/m) || [])[1];
      if (!loc) return null;
      return COUNTRY_LANG[loc] || null;
    } catch {
      return null;
    }
  }

  function fromQuery() {
    try {
      return normalize(new URLSearchParams(location.search).get("lang"));
    } catch {
      return null;
    }
  }

  function apply(code, opts) {
    const persist = !opts || opts.persist !== false;
    const lang = byCode[code] ? code : "en";
    const pack = STRINGS[lang] || STRINGS.en;
    const meta = byCode[lang] || byCode.en;

    document.documentElement.lang = lang === "zh-Hans" ? "zh-Hans" : lang.split("-")[0];
    document.documentElement.dir = meta.dir;

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      const val = pack[key] ?? STRINGS.en[key];
      if (val == null) return;
      if (el.tagName === "TITLE") {
        el.textContent = val;
        return;
      }
      if (el.hasAttribute("data-i18n-html")) {
        el.innerHTML = val;
      } else {
        el.textContent = val;
      }
    });

    document.querySelectorAll("[data-i18n-attr]").forEach((el) => {
      const spec = el.getAttribute("data-i18n-attr");
      // format: attr:key,attr:key
      spec.split(",").forEach((part) => {
        const [attr, key] = part.split(":").map((s) => s.trim());
        const val = pack[key] ?? STRINGS.en[key];
        if (attr && val != null) el.setAttribute(attr, val);
      });
    });

    const title = pack["meta.title"] || STRINGS.en["meta.title"];
    const desc = pack["meta.description"] || STRINGS.en["meta.description"];
    document.title = title;
    const metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc) metaDesc.setAttribute("content", desc);
    const ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle) ogTitle.setAttribute("content", title);
    const ogDesc = document.querySelector('meta[property="og:description"]');
    if (ogDesc) ogDesc.setAttribute("content", desc);

    const select = document.getElementById("lang-select");
    if (select && select.value !== lang) select.value = lang;

    if (persist) {
      try {
        localStorage.setItem(STORAGE_KEY, lang);
      } catch {
        /* ignore */
      }
    }

    document.documentElement.dataset.lang = lang;
  }

  function buildSelector() {
    const select = document.getElementById("lang-select");
    if (!select) return;
    select.innerHTML = "";
    LANGS.forEach((l) => {
      const opt = document.createElement("option");
      opt.value = l.code;
      opt.textContent = l.label;
      select.appendChild(opt);
    });
    select.addEventListener("change", () => apply(select.value));
  }

  async function boot() {
    buildSelector();

    const forced = fromQuery();
    if (forced) {
      apply(forced);
      return;
    }

    let saved = null;
    try {
      saved = normalize(localStorage.getItem(STORAGE_KEY));
    } catch {
      /* ignore */
    }
    if (saved) {
      apply(saved);
      return;
    }

    // Country first (user request), then browser Accept-Language, then English.
    // Do not persist until the final detected language is chosen.
    const provisional = fromBrowser() || "en";
    apply(provisional, { persist: false });

    const countryLang = await fromCountry();
    const finalLang = countryLang || provisional || "en";
    apply(finalLang);
  }

  window.FatnagI18n = { LANGS, apply, boot };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
