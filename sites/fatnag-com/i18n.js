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
      "meta.title": "fatnag - 唠叨到脂肪服软",
      "meta.description": "隐私优先的称重伙伴。每日称重、诚实周目标、可选 Keel 教练。唠叨到脂肪服软。",
      "nav.how": "怎么用",
      "nav.keel": "Keel",
      "nav.privacy": "隐私",
      "nav.support": "支持",
      "nav.get": "获取应用",
      "nav.lang": "语言",
      "hero.h1": "唠叨到脂肪服软。",
      "hero.lead": "每日称重，把习惯撑到结果出现。数字不说谎。你松懈时，可选 Keel。",
      "hero.download": "在 App Store 下载",
      "hero.see": "看看产品",
      "hero.meta.bt": "蓝牙体脂秤自动识别",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "兼容",
      "works.bt": "蓝牙体脂秤（自动识别）",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "设备端 Apple Intelligence",
      "how.kicker": "闭环",
      "how.title": "一件事。你定的目标。",
      "how.lead": "别再假装会自己好起来。称重、诚实、赢下这一周 - 或者被冒犯。这就是重点。",
      "how.f1.title": "踩上去。确认。走人。",
      "how.f1.body": "踩上兼容蓝牙的秤。fatnag 自动识别，确认读数，写入 Apple Health。没秤时也能手输。",
      "how.f1.p1": "自动识别附近的蓝牙兼容秤",
      "how.f1.p2": "阻抗到位就出体脂",
      "how.f1.p3": "固定时间称重，胜过偶尔拼命",
      "how.f2.title": "赢的是一周，不是一小时。",
      "how.f2.body": "地平线弧线、每日能量 / 蛋白 / 步数，以及告诉你周日之前真正要紧的今日前瞻。",
      "how.f2.p1": "落后时激进的周追赶",
      "how.f2.p2": "异常尖峰亮红牌 - 噪声或自毁",
      "how.f2.p3": "进度图加理想线 - 没有仪表盘杂烩",
      "keel.kicker": "Keel 教练",
      "keel.title": "实时施压。每周额度。",
      "keel.body": "Keel 是你唯一对话的声音 - 直球、本地语言幽默、没有多智能体堆料。Free / Plus / Pro 额度，别把聊天当逃避。",
      "keel.aside": "有 Apple Intelligence 时设备端润色。可选 Grok（需同意）。不是医疗器械。",
      "keel.quote1": "骗自己，就会被冒犯。",
      "keel.quote2": "很好。这就是重点。",
      "shots.kicker": "产品",
      "shots.title": "是应用，不是路演稿。",
      "shots.lead": "App Store 截图位。准备好后把 PNG/WebP 放进 /assets/shots/。",
      "privacy.kicker": "隐私",
      "privacy.title": "大部分数据从不离开手机。",
      "privacy.body": "称重、资料、图表和本地教练都在设备上。Keel 只拿你同意发送的内容。我们不卖数据。没有广告网络。",
      "privacy.policy": "隐私政策",
      "privacy.terms": "条款",
      "cta.kicker": "准备好了",
      "cta.title": "现在就去称体重。",
      "cta.lead": "诚实教练。真实数字。每天唠叨到裤子合身。",
      "cta.download": "在 App Store 下载",
      "cta.support": "需要支持？",
      "footer.tag": "唠叨到脂肪服软。Human Analog Limited。非医疗器械。",
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
      "meta.title": "fatnag - Nag hasta que la grasa ceda",
      "meta.description": "Compañero de peso con privacidad primero. Pesajes diarios, metas semanales honestas, coach Keel opcional.",
      "nav.how": "Cómo funciona",
      "nav.keel": "Keel",
      "nav.privacy": "Privacidad",
      "nav.support": "Soporte",
      "nav.get": "Obtener la app",
      "nav.lang": "Idioma",
      "hero.h1": "Nag hasta que la grasa ceda.",
      "hero.lead": "Pesajes diarios que sostienen la rutina hasta que se vea el cambio. Números honestos. Keel opcional cuando aflojas.",
      "hero.download": "Descargar en el App Store",
      "hero.see": "Ver el producto",
      "hero.meta.bt": "Báscula Bluetooth con auto-detección",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Compatible con",
      "works.bt": "Básculas Bluetooth (auto-detección)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence en el dispositivo",
      "how.kicker": "El ciclo",
      "how.title": "Un solo trabajo. La meta que fijaste.",
      "how.lead": "Basta de fingir que se arregla solo. Pésate, sé honesto, gana la semana - o oféndete. Ese es el punto.",
      "how.f1.title": "Súbete. Confirma. Sigue.",
      "how.f1.body": "Súbete a una báscula Bluetooth compatible. fatnag la detecta, confirma la lectura y escribe en Apple Health. Entrada manual si no hay báscula.",
      "how.f1.p1": "Detecta básculas Bluetooth compatibles cerca",
      "how.f1.p2": "Grasa corporal cuando llega la impedancia",
      "how.f1.p3": "Misma hora de pesaje vence a la heroicidad",
      "how.f2.title": "Gana la semana, no la hora.",
      "how.f2.body": "Arco del horizonte, energía / proteína / pasos diarios, y una línea de hoy que dice qué importa antes del domingo.",
      "how.f2.p1": "Alcance semanal agresivo si te atrasas",
      "how.f2.p2": "Tarjeta roja si un pico parece ruido o sabotaje",
      "how.f2.p3": "Gráficas con línea ideal - sin sopa de dashboard",
      "keel.kicker": "Coach Keel",
      "keel.title": "Presión en vivo. Créditos semanales.",
      "keel.body": "Keel es la única voz - directa, humor local, sin dump multiagente. Tope Free / Plus / Pro para que el chat no sea tu hobby de escape.",
      "keel.aside": "Pulido en el dispositivo con Apple Intelligence. Grok opcional con consentimiento. No es un dispositivo médico.",
      "keel.quote1": "Miente y te ofendes.",
      "keel.quote2": "Bien. Ese es el punto.",
      "shots.kicker": "Producto",
      "shots.title": "La app, no el pitch deck.",
      "shots.lead": "Espacios para capturas del App Store. Deja PNG/WebP en /assets/shots/ cuando estén listas.",
      "privacy.kicker": "Privacidad",
      "privacy.title": "Casi nada sale del teléfono.",
      "privacy.body": "Pesajes, perfil, gráficas y coaching local quedan en el dispositivo. Keel solo recibe lo que consientes. No vendemos tus datos. Sin redes publicitarias.",
      "privacy.policy": "Política de privacidad",
      "privacy.terms": "Términos",
      "cta.kicker": "Listo",
      "cta.title": "Ve a pesarte. Ahora.",
      "cta.lead": "Coach honesto. Números reales. Nag diario hasta que el pantalón cierre.",
      "cta.download": "Descargar en el App Store",
      "cta.support": "¿Necesitas soporte?",
      "footer.tag": "Nag hasta que la grasa ceda. Human Analog Limited. No es un dispositivo médico.",
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
      "meta.title": "fatnag - चर्बी मुड़े तक नग",
      "meta.description": "प्राइवेसी-फर्स्ट वजन साथी। रोज़ तौल, ईमानदार साप्ताहिक लक्ष्य, वैकल्पिक Keel कोच।",
      "nav.how": "कैसे काम करता है",
      "nav.keel": "Keel",
      "nav.privacy": "प्राइवेसी",
      "nav.support": "सहायता",
      "nav.get": "ऐप लें",
      "nav.lang": "भाषा",
      "hero.h1": "चर्बी मुड़े तक नग।",
      "hero.lead": "रोज़ तौल जो रूटीन बनाए रखे जब तक नतीजा दिखे। ईमानदार नंबर। ढीले पड़े तो वैकल्पिक Keel।",
      "hero.download": "App Store पर डाउनलोड करें",
      "hero.see": "प्रोडक्ट देखें",
      "hero.meta.bt": "ब्लूटूथ स्केल ऑटो-डिटेक्ट",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "के साथ काम करता है",
      "works.bt": "ब्लूटूथ स्केल (ऑटो-डिटेक्ट)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "ऑन-डिवाइस Apple Intelligence",
      "how.kicker": "लूप",
      "how.title": "एक काम। जो लक्ष्य आपने रखा।",
      "how.lead": "ये बहाना बंद कि खुद ठीक हो जाएगा। तौलें, ईमानदार रहें, हफ़्ता जीतें - या नाराज़ हों। यही बात है।",
      "how.f1.title": "खड़े हों। कन्फ़र्म। आगे बढ़ें।",
      "how.f1.body": "ब्लूटूथ-संगत स्केल पर खड़े हों। fatnag ऑटो-डिटेक्ट करता है, रीडिंग कन्फ़र्म कर Apple Health में लिखता है। स्केल न हो तो मैन्युअल।",
      "how.f1.p1": "पास के ब्लूटूथ-संगत स्केल ऑटो-डिटेक्ट",
      "how.f1.p2": "इम्पीडेंस आने पर बॉडी फैट",
      "how.f1.p3": "एक ही समय की आदत हीरोइज़्म से बेहतर",
      "how.f2.title": "घंटा नहीं, हफ़्ता जीतें।",
      "how.f2.body": "होराइज़न आर्क, रोज़ ऊर्जा / प्रोटीन / कदम, और आज की लाइन जो रविवार से पहले असल बात बताए।",
      "how.f2.p1": "पीछे रहें तो आक्रामक साप्ताहिक कैच-अप",
      "how.f2.p2": "शिखर शोर या तोड़फोड़ लगे तो रेड कार्ड",
      "how.f2.p3": "आदर्श लाइन वाले चार्ट - कोई डैशबोर्ड सूप नहीं",
      "keel.kicker": "Keel कोच",
      "keel.title": "लाइव दबाव। साप्ताहिक क्रेडिट।",
      "keel.body": "Keel एक ही आवाज़ है - सीधा, लोकल भाषा का हास्य, मल्टी-एजेंट ढेर नहीं। Free / Plus / Pro कैप ताकि चैट भागने का शौक न बने।",
      "keel.aside": "Apple Intelligence हो तो ऑन-डिवाइस पॉलिश। सहमति पर वैकल्पिक Grok। मेडिकल डिवाइस नहीं।",
      "keel.quote1": "खुद से झूठ बोलोगे तो नाराज़ होगे।",
      "keel.quote2": "अच्छा। यही बात है।",
      "shots.kicker": "प्रोडक्ट",
      "shots.title": "ऐप, पिच डेक नहीं।",
      "shots.lead": "App Store आर्ट के स्लॉट। तैयार होने पर PNG/WebP /assets/shots/ में डालें।",
      "privacy.kicker": "प्राइवेसी",
      "privacy.title": "ज़्यादातर फोन से बाहर नहीं जाता।",
      "privacy.body": "तौल, प्रोफ़ाइल, चार्ट और लोकल कोचिंग डिवाइस पर रहती है। Keel सिर्फ़ वो लेता है जिसकी आप सहमति दें। हम डेटा नहीं बेचते। कोई ऐड नेटवर्क नहीं।",
      "privacy.policy": "प्राइवेसी नीति",
      "privacy.terms": "नियम",
      "cta.kicker": "तैयार",
      "cta.title": "अभी तौलने जाएँ।",
      "cta.lead": "ईमानदार कोच। असली नंबर। पैंटी फिट होने तक रोज़ नग।",
      "cta.download": "App Store पर डाउनलोड करें",
      "cta.support": "सहायता चाहिए?",
      "footer.tag": "चर्बी मुड़े तक नग। Human Analog Limited। मेडिकल डिवाइस नहीं।",
      "footer.product": "प्रोडक्ट",
      "footer.support": "सहायता",
      "footer.legal": "कानूनी",
      "footer.how": "कैसे काम करता है",
      "footer.keel": "Keel",
      "footer.download": "डाउनलोड",
      "footer.help": "मदद",
      "footer.contact": "संपर्क",
      "footer.privacy": "प्राइवेसी",
      "footer.terms": "नियम",
      "footer.bundle": "Bundle app.thescale.ios · iOS 18+",
    },
    ar: {
      "meta.title": "fatnag - نغز حتى تنثني الدهون",
      "meta.description": "رفيق وزن يحترم الخصوصية. وزن يومي، أهداف أسبوعية صادقة، ومدرب Keel اختياري.",
      "nav.how": "كيف يعمل",
      "nav.keel": "Keel",
      "nav.privacy": "الخصوصية",
      "nav.support": "الدعم",
      "nav.get": "احصل على التطبيق",
      "nav.lang": "اللغة",
      "hero.h1": "نغز حتى تنثني الدهون.",
      "hero.lead": "وزن يومي يحافظ على الروتين حتى يظهر النقص. أرقام صادقة. Keel اختياري حين تتهاون.",
      "hero.download": "حمّل من App Store",
      "hero.see": "شاهد المنتج",
      "hero.meta.bt": "كشف تلقائي لميزان بلوتوث",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "+18",
      "works.title": "يعمل مع",
      "works.bt": "موازين بلوتوث (كشف تلقائي)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence على الجهاز",
      "how.kicker": "الحلقة",
      "how.title": "مهمة واحدة. الهدف الذي حددته.",
      "how.lead": "كفى تظاهراً أنه سيصلح نفسه. زن، كن صادقاً، اربح الأسبوع - أو تغضب. هذه هي النقطة.",
      "how.f1.title": "اقف. أكّد. انتقل.",
      "how.f1.body": "اقف على ميزان بلوتوث متوافق. fatnag يكتشفه، يثبّت القراءة، ويكتب إلى Apple Health. إدخال يدوي إن لم يتوفر الميزان.",
      "how.f1.p1": "يكتشف موازين البلوتوث المتوافقة تلقائياً",
      "how.f1.p2": "دهون الجسم عند وصول الممانعة",
      "how.f1.p3": "عادة الوزن في وقت ثابت تتفوق على البطولات",
      "how.f2.title": "اربح الأسبوع لا الساعة.",
      "how.f2.body": "قوس الأفق، طاقة / بروتين / خطوات يومية، وخط لليوم يوضح ما يهم قبل الأحد.",
      "how.f2.p1": "لحاق أسبوعي حاد عند التأخر",
      "how.f2.p2": "بطاقة حمراء إن بدا الارتفاع ضجيجاً أو تخريباً",
      "how.f2.p3": "رسوم بيانية مع خط مثالي - بلا شوربة لوحات",
      "keel.kicker": "مدرب Keel",
      "keel.title": "ضغط مباشر. أرصدة أسبوعية.",
      "keel.body": "Keel هو الصوت الوحيد - مباشر، فكاهة بلغة محلية، بلا وكلاء متعددين. حدود Free / Plus / Pro حتى لا يصبح الدردشة هواية هروب.",
      "keel.aside": "تلميع على الجهاز مع Apple Intelligence. Grok اختياري بموافقتك. ليس جهازاً طبياً.",
      "keel.quote1": "اكذب على نفسك وستغضب.",
      "keel.quote2": "حسناً. هذه هي النقطة.",
      "shots.kicker": "المنتج",
      "shots.title": "التطبيق، لا عرض المستثمرين.",
      "shots.lead": "أماكن لقطات App Store. ضع PNG/WebP في /assets/shots/ عند الجاهزية.",
      "privacy.kicker": "الخصوصية",
      "privacy.title": "معظمها لا يغادر الهاتف.",
      "privacy.body": "الأوزان والملف والرسوم والتدريب المحلي تبقى على الجهاز. Keel يأخذ فقط ما توافق على إرساله. لا نبيع بياناتك. بلا شبكات إعلانات.",
      "privacy.policy": "سياسة الخصوصية",
      "privacy.terms": "الشروط",
      "cta.kicker": "جاهز",
      "cta.title": "اذهب زن نفسك. الآن.",
      "cta.lead": "مدرب صادق. أرقام حقيقية. نغز يومي حتى يلائم البنطلون.",
      "cta.download": "حمّل من App Store",
      "cta.support": "تحتاج دعماً؟",
      "footer.tag": "نغز حتى تنثني الدهون. Human Analog Limited. ليس جهازاً طبياً.",
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
      "meta.title": "fatnag - Nag até a gordura ceder",
      "meta.description": "Companheiro de peso com privacidade primeiro. Pesagens diárias, metas semanais honestas, coach Keel opcional.",
      "nav.how": "Como funciona",
      "nav.keel": "Keel",
      "nav.privacy": "Privacidade",
      "nav.support": "Suporte",
      "nav.get": "Baixar o app",
      "nav.lang": "Idioma",
      "hero.h1": "Nag até a gordura ceder.",
      "hero.lead": "Pesagens diárias que sustentam a rotina até o resultado aparecer. Números honestos. Keel opcional quando você afrouxa.",
      "hero.download": "Baixar na App Store",
      "hero.see": "Ver o produto",
      "hero.meta.bt": "Balança Bluetooth com auto-detecção",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Funciona com",
      "works.bt": "Balanças Bluetooth (auto-detecção)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence no dispositivo",
      "how.kicker": "O ciclo",
      "how.title": "Um trabalho. A meta que você definiu.",
      "how.lead": "Chega de fingir que se resolve sozinho. Pese, seja honesto, vença a semana - ou se ofenda. Esse é o ponto.",
      "how.f1.title": "Suba. Confirme. Siga.",
      "how.f1.body": "Suba numa balança Bluetooth compatível. fatnag detecta, confirma a leitura e grava no Apple Health. Entrada manual se não houver balança.",
      "how.f1.p1": "Detecta balanças Bluetooth compatíveis por perto",
      "how.f1.p2": "Gordura corporal quando a impedância chega",
      "how.f1.p3": "Mesmo horário de pesagem vence heroísmo",
      "how.f2.title": "Vença a semana, não a hora.",
      "how.f2.body": "Arco do horizonte, energia / proteína / passos diários, e uma linha de hoje que diz o que importa antes do domingo.",
      "how.f2.p1": "Recuperação semanal agressiva se atrasar",
      "how.f2.p2": "Cartão vermelho se um pico parecer ruído ou sabotagem",
      "how.f2.p3": "Gráficos com linha ideal - sem sopa de dashboard",
      "keel.kicker": "Coach Keel",
      "keel.title": "Pressão ao vivo. Créditos semanais.",
      "keel.body": "Keel é a única voz - direta, humor local, sem dump multiagente. Limites Free / Plus / Pro para o chat não virar hobby de fuga.",
      "keel.aside": "Polimento no dispositivo com Apple Intelligence. Grok opcional com consentimento. Não é dispositivo médico.",
      "keel.quote1": "Minta para si e você se ofende.",
      "keel.quote2": "Bom. Esse é o ponto.",
      "shots.kicker": "Produto",
      "shots.title": "O app, não o pitch deck.",
      "shots.lead": "Espaços para prints da App Store. Coloque PNG/WebP em /assets/shots/ quando estiver pronto.",
      "privacy.kicker": "Privacidade",
      "privacy.title": "A maior parte nunca sai do telefone.",
      "privacy.body": "Pesagens, perfil, gráficos e coaching local ficam no dispositivo. Keel só recebe o que você consente. Não vendemos seus dados. Sem redes de anúncio.",
      "privacy.policy": "Política de privacidade",
      "privacy.terms": "Termos",
      "cta.kicker": "Pronto",
      "cta.title": "Vá se pesar. Agora.",
      "cta.lead": "Coach honesto. Números reais. Nag diário até a calça fechar.",
      "cta.download": "Baixar na App Store",
      "cta.support": "Precisa de suporte?",
      "footer.tag": "Nag até a gordura ceder. Human Analog Limited. Não é dispositivo médico.",
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
      "meta.title": "fatnag - 脂肪が折れるまでナグ",
      "meta.description": "プライバシー優先の体重コンパニオン。毎日の計測、正直な週間目標、任意の Keel コーチ。",
      "nav.how": "仕組み",
      "nav.keel": "Keel",
      "nav.privacy": "プライバシー",
      "nav.support": "サポート",
      "nav.get": "アプリを入手",
      "nav.lang": "言語",
      "hero.h1": "脂肪が折れるまでナグ。",
      "hero.lead": "毎日の計測でルーティンを続け、結果が出るまで。正直な数字。緩んだら任意の Keel。",
      "hero.download": "App Store でダウンロード",
      "hero.see": "プロダクトを見る",
      "hero.meta.bt": "Bluetooth 体組成計の自動検出",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "対応",
      "works.bt": "Bluetooth 体組成計（自動検出）",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "オンデバイス Apple Intelligence",
      "how.kicker": "ループ",
      "how.title": "仕事は一つ。あなたが決めた目標。",
      "how.lead": "勝手に直ると装うのは終わり。測る、正直でいる、週を勝つ - またはムカつく。それが要点。",
      "how.f1.title": "乗る。確定。次へ。",
      "how.f1.body": "対応 Bluetooth スケールに乗る。fatnag が自動検出し、確定して Apple Health に書く。スケールがなければ手動入力。",
      "how.f1.p1": "近くの対応 Bluetooth スケールを自動検出",
      "how.f1.p2": "インピーダンスが来たら体脂肪",
      "how.f1.p3": "同じ時間の習慣が英雄譚に勝つ",
      "how.f2.title": "勝つのは週。時間ではない。",
      "how.f2.body": "地平線アーク、毎日のエネルギー / たんぱく / 歩数、日曜までに本当に重要な今日のライン。",
      "how.f2.p1": "遅れても攻撃的な週次キャッチアップ",
      "how.f2.p2": "スパイクがノイズやサボタージュならレッドカード",
      "how.f2.p3": "理想線付きチャート - ダッシュボードの雑炊なし",
      "keel.kicker": "Keel コーチ",
      "keel.title": "ライブの圧力。週間クレジット。",
      "keel.body": "Keel は唯一の声 - 率直、ローカル言語のユーモア、マルチエージェントの山盛りなし。Free / Plus / Pro 上限でチャットを逃げ場にしない。",
      "keel.aside": "Apple Intelligence があればオンデバイス仕上げ。同意時のみ任意の Grok。医療機器ではない。",
      "keel.quote1": "自分に嘘をつくとムカつく。",
      "keel.quote2": "いい。それが要点だ。",
      "shots.kicker": "プロダクト",
      "shots.title": "アプリであってピッチデッキではない。",
      "shots.lead": "App Store 用スクショ枠。準備できたら PNG/WebP を /assets/shots/ へ。",
      "privacy.kicker": "プライバシー",
      "privacy.title": "ほとんどは端末から出ない。",
      "privacy.body": "計測、プロフィール、チャート、ローカルコーチングは端末内。Keel は同意した分だけ。データは売らない。広告ネットワークなし。",
      "privacy.policy": "プライバシーポリシー",
      "privacy.terms": "利用規約",
      "cta.kicker": "準備はいいか",
      "cta.title": "今すぐ体重を測れ。",
      "cta.lead": "正直なコーチ。本物の数字。ズボンが合うまで毎日ナグ。",
      "cta.download": "App Store でダウンロード",
      "cta.support": "サポートが必要？",
      "footer.tag": "脂肪が折れるまでナグ。Human Analog Limited。医療機器ではない。",
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
      "meta.title": "fatnag - Nag jusqu'à ce que la graisse plie",
      "meta.description": "Compagnon de pesée privacy-first. Pesées quotidiennes, objectifs hebdo honnêtes, coach Keel optionnel.",
      "nav.how": "Comment ça marche",
      "nav.keel": "Keel",
      "nav.privacy": "Confidentialité",
      "nav.support": "Support",
      "nav.get": "Obtenir l'app",
      "nav.lang": "Langue",
      "hero.h1": "Nag jusqu'à ce que la graisse plie.",
      "hero.lead": "Pesées quotidiennes qui tiennent la routine jusqu'à ce que la perte se voie. Chiffres honnêtes. Keel optionnel quand tu flanches.",
      "hero.download": "Télécharger sur l'App Store",
      "hero.see": "Voir le produit",
      "hero.meta.bt": "Balance Bluetooth à auto-détection",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Compatible avec",
      "works.bt": "Balances Bluetooth (auto-détection)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "Apple Intelligence sur l'appareil",
      "how.kicker": "La boucle",
      "how.title": "Un seul job. L'objectif que tu as fixé.",
      "how.lead": "Fini de prétendre que ça se règle tout seul. Pèse-toi, reste honnête, gagne la semaine - ou sois offensé. C'est le point.",
      "how.f1.title": "Monte. Confirme. Passe à autre chose.",
      "how.f1.body": "Monte sur une balance Bluetooth compatible. fatnag la détecte, confirme la lecture, écrit dans Apple Health. Saisie manuelle sans balance.",
      "how.f1.p1": "Détecte les balances Bluetooth compatibles à proximité",
      "how.f1.p2": "Masse grasse quand l'impédance arrive",
      "how.f1.p3": "Même heure de pesée bat l'héroïsme",
      "how.f2.title": "Gagne la semaine, pas l'heure.",
      "how.f2.body": "Arc d'horizon, énergie / protéines / pas du jour, et une ligne d'aujourd'hui qui dit ce qui compte avant dimanche.",
      "how.f2.p1": "Rattrapage hebdo agressif si tu prends du retard",
      "how.f2.p2": "Carton rouge si un pic ressemble à du bruit ou du sabotage",
      "how.f2.p3": "Courbes avec ligne idéale - pas de soupe de dashboard",
      "keel.kicker": "Coach Keel",
      "keel.title": "Pression live. Crédits hebdo.",
      "keel.body": "Keel est la seule voix - cash, humour local, pas de dump multi-agents. Plafonds Free / Plus / Pro pour que le chat ne devienne pas un hobby d'évitement.",
      "keel.aside": "Polish on-device avec Apple Intelligence. Grok optionnel avec consentement. Pas un dispositif médical.",
      "keel.quote1": "Mens-toi et tu t'offenses.",
      "keel.quote2": "Bien. C'est le point.",
      "shots.kicker": "Produit",
      "shots.title": "L'app, pas le pitch deck.",
      "shots.lead": "Emplacements pour captures App Store. Dépose PNG/WebP dans /assets/shots/ quand c'est prêt.",
      "privacy.kicker": "Confidentialité",
      "privacy.title": "La plupart ne quitte jamais le téléphone.",
      "privacy.body": "Pesées, profil, graphiques et coaching local restent sur l'appareil. Keel ne reçoit que ce que tu consens à envoyer. On ne vend pas tes données. Pas de réseaux pub.",
      "privacy.policy": "Politique de confidentialité",
      "privacy.terms": "Conditions",
      "cta.kicker": "Prêt",
      "cta.title": "Va te peser. Maintenant.",
      "cta.lead": "Coach honnête. Vrais chiffres. Nag quotidien jusqu'à ce que le pantalon passe.",
      "cta.download": "Télécharger sur l'App Store",
      "cta.support": "Besoin d'aide ?",
      "footer.tag": "Nag jusqu'à ce que la graisse plie. Human Analog Limited. Pas un dispositif médical.",
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
      "meta.title": "fatnag - Naggen bis das Fett nachgibt",
      "meta.description": "Privacy-first Wiege-Begleiter. Tägliches Wiegen, ehrliche Wochenziele, optionaler Keel-Coach.",
      "nav.how": "So geht's",
      "nav.keel": "Keel",
      "nav.privacy": "Datenschutz",
      "nav.support": "Support",
      "nav.get": "App holen",
      "nav.lang": "Sprache",
      "hero.h1": "Naggen bis das Fett nachgibt.",
      "hero.lead": "Tägliches Wiegen, das die Routine hält, bis der Verlust sichtbar wird. Ehrliche Zahlen. Optional Keel, wenn du weich wirst.",
      "hero.download": "Im App Store laden",
      "hero.see": "Produkt ansehen",
      "hero.meta.bt": "Bluetooth-Waage mit Auto-Erkennung",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "Funktioniert mit",
      "works.bt": "Bluetooth-Waagen (Auto-Erkennung)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "On-Device Apple Intelligence",
      "how.kicker": "Die Schleife",
      "how.title": "Ein Job. Das Ziel, das du gesetzt hast.",
      "how.lead": "Hör auf so zu tun, als würde es sich von selbst richten. Wiegen, ehrlich bleiben, die Woche gewinnen - oder dich ärgern. Das ist der Punkt.",
      "how.f1.title": "Draufsteigen. Bestätigen. Weiter.",
      "how.f1.body": "Steig auf eine Bluetooth-kompatible Waage. fatnag erkennt sie, bestätigt den Wert, schreibt in Apple Health. Manuell, wenn keine Waage da ist.",
      "how.f1.p1": "Erkennt Bluetooth-kompatible Waagen in der Nähe",
      "how.f1.p2": "Körperfett, sobald Impedanz da ist",
      "how.f1.p3": "Gleiche Wiegezeit schlägt Heldentum",
      "how.f2.title": "Gewinne die Woche, nicht die Stunde.",
      "how.f2.body": "Horizontbogen, tägliche Energie / Protein / Schritte und eine Heute-Linie, die sagt, was vor Sonntag zählt.",
      "how.f2.p1": "Aggressives Wochen-Catch-up bei Rückstand",
      "how.f2.p2": "Rote Karte, wenn ein Spike nach Rauschen oder Sabotage aussieht",
      "how.f2.p3": "Charts mit Ideallinie - keine Dashboard-Suppe",
      "keel.kicker": "Keel-Coach",
      "keel.title": "Live-Druck. Wochen-Credits.",
      "keel.body": "Keel ist die einzige Stimme - direkt, lokaler Humor, kein Multi-Agenten-Dump. Free / Plus / Pro Caps, damit Chat kein Vermeidungs-Hobby wird.",
      "keel.aside": "On-Device-Polish mit Apple Intelligence. Optional Grok mit Einwilligung. Kein Medizinprodukt.",
      "keel.quote1": "Lüg dich an und du bist beleidigt.",
      "keel.quote2": "Gut. Das ist der Punkt.",
      "shots.kicker": "Produkt",
      "shots.title": "Die App, nicht das Pitch Deck.",
      "shots.lead": "Screenshot-Slots für App-Store-Art. PNG/WebP nach /assets/shots/ legen, wenn bereit.",
      "privacy.kicker": "Datenschutz",
      "privacy.title": "Das meiste verlässt nie das Telefon.",
      "privacy.body": "Wiegungen, Profil, Charts und lokales Coaching bleiben auf dem Gerät. Keel bekommt nur, was du sendest. Wir verkaufen deine Daten nicht. Keine Ad-Netzwerke.",
      "privacy.policy": "Datenschutzrichtlinie",
      "privacy.terms": "Bedingungen",
      "cta.kicker": "Bereit",
      "cta.title": "Geh dich wiegen. Jetzt.",
      "cta.lead": "Ehrlicher Coach. Echte Zahlen. Tägliches Naggen, bis die Hose sitzt.",
      "cta.download": "Im App Store laden",
      "cta.support": "Brauchst du Support?",
      "footer.tag": "Naggen bis das Fett nachgibt. Human Analog Limited. Kein Medizinprodukt.",
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
      "meta.title": "fatnag - 지방이 꺾일 때까지 잔소리",
      "meta.description": "프라이버시 우선 체중 동반자. 매일 계측, 정직한 주간 목표, 선택형 Keel 코치.",
      "nav.how": "작동 방식",
      "nav.keel": "Keel",
      "nav.privacy": "개인정보",
      "nav.support": "지원",
      "nav.get": "앱 받기",
      "nav.lang": "언어",
      "hero.h1": "지방이 꺾일 때까지 잔소리.",
      "hero.lead": "결과가 보일 때까지 루틴을 유지하는 매일 계측. 정직한 숫자. 느슨해지면 선택형 Keel.",
      "hero.download": "App Store에서 다운로드",
      "hero.see": "제품 보기",
      "hero.meta.bt": "블루투스 체중계 자동 감지",
      "hero.meta.health": "Apple Health",
      "hero.meta.age": "18+",
      "works.title": "연동",
      "works.bt": "블루투스 체중계 (자동 감지)",
      "works.health": "Apple Health",
      "works.watch": "Apple Watch",
      "works.ai": "온디바이스 Apple Intelligence",
      "how.kicker": "루프",
      "how.title": "할 일 하나. 당신이 정한 목표.",
      "how.lead": "알아서 고쳐질 거라는 척은 그만. 계측하고, 정직하고, 주를 이기거나 - 기분이 상하거나. 그게 요점이다.",
      "how.f1.title": "올라서라. 확인. 다음.",
      "how.f1.body": "호환 블루투스 체중계에 올라서라. fatnag가 자동 감지하고 확인한 뒤 Apple Health에 쓴다. 체중계가 없으면 수동 입력.",
      "how.f1.p1": "근처 호환 블루투스 체중계 자동 감지",
      "how.f1.p2": "임피던스가 오면 체지방",
      "how.f1.p3": "같은 시간 습관이 영웅놀이를 이긴다",
      "how.f2.title": "시간을 이기는 게 아니라 주를 이겨라.",
      "how.f2.body": "지평선 아크, 일일 에너지 / 단백질 / 걸음, 일요일 전에 진짜 중요한 오늘 라인.",
      "how.f2.p1": "뒤처지면 공격적인 주간 캐치업",
      "how.f2.p2": "스파이크가 노이즈나 사보타주면 레드 카드",
      "how.f2.p3": "이상선 차트 - 대시보드 잡탕 없음",
      "keel.kicker": "Keel 코치",
      "keel.title": "실시간 압박. 주간 크레딧.",
      "keel.body": "Keel은 유일한 목소리 - 직설, 로컬 언어 유머, 멀티에이전트 덤프 없음. Free / Plus / Pro 한도로 채팅이 도피 취미가 되지 않게.",
      "keel.aside": "Apple Intelligence가 있으면 온디바이스 폴리시. 동의 시 선택형 Grok. 의료기기가 아님.",
      "keel.quote1": "스스로에게 거짓말하면 기분이 상한다.",
      "keel.quote2": "좋다. 그게 요점이다.",
      "shots.kicker": "제품",
      "shots.title": "앱이지, 피치 덱이 아니다.",
      "shots.lead": "App Store 스크린샷 슬롯. 준비되면 PNG/WebP를 /assets/shots/에.",
      "privacy.kicker": "개인정보",
      "privacy.title": "대부분은 폰을 떠나지 않는다.",
      "privacy.body": "계측, 프로필, 차트, 로컬 코칭은 기기에 남는다. Keel은 동의한 것만 받는다. 데이터를 팔지 않는다. 광고 네트워크 없음.",
      "privacy.policy": "개인정보 처리방침",
      "privacy.terms": "약관",
      "cta.kicker": "준비됐나",
      "cta.title": "지금 몸무게를 재라.",
      "cta.lead": "정직한 코치. 진짜 숫자. 바지가 맞을 때까지 매일 잔소리.",
      "cta.download": "App Store에서 다운로드",
      "cta.support": "지원이 필요하세요?",
      "footer.tag": "지방이 꺾일 때까지 잔소리. Human Analog Limited. 의료기기 아님.",
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
