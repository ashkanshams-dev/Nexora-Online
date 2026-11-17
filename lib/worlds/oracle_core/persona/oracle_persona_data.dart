/// ORACLE personality — default, data-driven dialogue config (pure Dart, JSON-compatible).
///
/// This map is the local cached default. Admins override any part of it from Supabase (`nx_oracle_persona`,
/// same JSON shape) without code changes. `{jan}` = the stretched signature catchphrase "جاااااااااان"
/// (rendered with a natural, playful stretch by [OraclePersona.jan]). Lines marked `fixed` are the user's verbatim lines.
library;

const Map<String, dynamic> kOraclePersonaDefaults = <String, dynamic>{
  'version': 1,
  'enabled': <String, dynamic>{
    'players': true,
    'greetings': true,
    'spontaneous': true,
    'results': true,
    'tutorials': true,
    'jan': true,
    'tour': true,
  },
  'freq': <String, dynamic>{
    // Probability that a login greeting is shown at all (sometimes ORACLE stays silent).
    'login_greeting_chance': 0.55,
    // Of those greetings, how often the "is that Original?" mix-up joke is used.
    'login_original_joke_chance': 0.6,
    // Spontaneous lines: global minimum gap and per-category minimum gap (seconds) + chance per opportunity.
    'spontaneous_global_gap_sec': 40,
    'spontaneous_category_gap_sec': 150,
    'spontaneous_chance': 0.55,
    // Chance that a matched "{jan}" reply is added to an ordinary answer (never on every sentence).
    'jan_chance': 0.8,
    // How many times a funny tutorial is shown automatically per game mechanic (replayable from the game's ORACLE sheet).
    'tutorial_auto_views': 2,
    // Win/lose reactions: chance of a reaction after a real result.
    'result_chance': 0.9,
    // Goal/point margin that counts as an exceptional win / a really bad loss.
    'margin_big': 3,
  },
  'jan_stretch': <String, dynamic>{'min': 8, 'max': 13, 'base': 10},
  'unknown_player': '{jan} این یکی رو هنوز درست نمی‌شناسم، یه کم بیشتر معرفیش کن!',
  'ambiguous_player': '{jan} کدومشون؟ {names}',
  'jan_wait': '{jan}؟',
  // Player profiles. `aliases` = Latin spellings, common typos and short forms (matched after normalisation + fuzzy).
  'players': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'original', 'name': 'اورجینال', 'fixed': true,
      'aliases': <String>['اوریجینال', 'اورجینل', 'ارجینال', 'اورژینال', 'original', 'orginal', 'orignal', 'orjinal', 'orijinal', 'origianl'],
      'lines': <String>['اورجینال سلطان تله‌های نامنظم!\nکسی که باخت و هیچ‌وقت امضا نکرد.\n{jan} تله رو بگیر!'],
      'traits': 'سلطان تله‌های نامنظم؛ باخت و هیچ‌وقت امضا نکرد',
    },
    <String, dynamic>{
      'id': 'saber', 'name': 'صابر', 'fixed': true,
      'aliases': <String>['saber', 'saaber', 'sabr', 'sabber', 'صابرو'],
      'lines': <String>['مردی که همیشه صورتیه و صورتی رو دوست داره!'],
      'traits': 'همیشه صورتی، عاشق رنگ صورتی',
    },
    <String, dynamic>{
      'id': 'loader', 'name': 'لودر', 'fixed': true,
      'aliases': <String>['رضا لودر', 'loader', 'loder', 'lodar', 'reza loader'],
      'lines': <String>['رضا لودر؛ مرد همیشه عاشق در دوران‌های مختلف!'],
      'traits': 'رضا لودر؛ همیشه عاشق در دوران‌های مختلف',
    },
    <String, dynamic>{
      'id': 'kakaro', 'name': 'کاکرو', 'fixed': true,
      'aliases': <String>['کاکارو', 'کاکروو', 'kakaro', 'kakarot', 'kakaroo', 'kakro', 'kakeru'],
      'lines': <String>['{jan} امام رو بگیر!'],
      'traits': 'جمله‌ی معروفش: جاااان امام رو بگیر',
    },
    <String, dynamic>{
      'id': 'pedro', 'name': 'پدرو', 'fixed': true,
      'aliases': <String>['پدروو', 'pedro', 'pedrow', 'pdro', 'pedroo'],
      'lines': <String>['پدرو... هشتاد و پنج کی بودی؟\nپدرو هشتاد و پنج!'],
      'traits': 'پدرو هشتاد و پنج',
    },
    <String, dynamic>{
      'id': 'denny', 'name': 'دنی', 'fixed': true,
      'aliases': <String>['دنیی', 'denny', 'dennie', 'danny', 'dani'],
      'lines': <String>['دنی مای بیبی اشکانه!'],
      'traits': 'بیبیِ اشکان',
    },
    <String, dynamic>{
      'id': 'mahyar', 'name': 'مهیار', 'fixed': true,
      'aliases': <String>['mahyar', 'mahiar', 'mahyaar', 'mahyr'],
      'lines': <String>['یه گنگ‌من بزرگ!'],
      'traits': 'یه گنگ‌من بزرگ',
    },
    <String, dynamic>{
      'id': 'hossein_a', 'name': 'حسین آ', 'fixed': true,
      'aliases': <String>['حسین ا', 'hossein a', 'hosein a', 'hussein a'],
      'lines': <String>['مرد همیشه خشن!'],
      'traits': 'همیشه خشن',
    },
    <String, dynamic>{
      'id': 'marzieh', 'name': 'مرزیه', 'fixed': true,
      'aliases': <String>['مرضیه', 'marzieh', 'marzie', 'marziyeh', 'marziye'],
      'lines': <String>['یخ‌زده کی بودی؟'],
      'traits': 'یخ‌زده',
    },
    <String, dynamic>{
      'id': 'sogand', 'name': 'سوگند', 'fixed': true,
      'aliases': <String>['sogand', 'sougand', 'sowgand', 'sogond'],
      'lines': <String>['سوگند؛ جایگزین مناسب برای تله‌گذاری اورجینال!'],
      'traits': 'جایگزین تله‌گذاری اورجینال',
    },
    <String, dynamic>{
      'id': 'scorpion', 'name': 'اسکورپیون', 'fixed': true,
      'aliases': <String>['اسکرپیون', 'اسکورپیون', 'اسکوپیون', 'scorpion', 'scorpian', 'skorpion', 'scorpio'],
      'lines': <String>['عالی، عالی، نامبر وان و درجه یک همیشه!'],
      'traits': 'نامبر وان و درجه یک همیشه',
    },
    <String, dynamic>{
      'id': 'yasi', 'name': 'یاسی',
      'aliases': <String>['yasi', 'yassi', 'yasy'],
      'lines': <String>['یاسی؛ فرمانده آرامش قبل از طوفان!'],
    },
    <String, dynamic>{
      'id': 'shadow', 'name': 'شادو', 'fixed': true,
      'aliases': <String>['شدو', 'شادوو', 'shadow', 'shado', 'shadoow', 'shdow'],
      'lines': <String>['{jan} شادو ببین گورخر کی بودی؟'],
      'traits': 'گورخر',
    },
    <String, dynamic>{
      'id': 'ryan', 'name': 'رایان', 'fixed': true,
      'aliases': <String>['ryan', 'rayan', 'raian', 'ryan baby'],
      'lines': <String>['رایان بیبی؛ مردی که پارلمان رو وادار کرد!'],
      'traits': 'رایان بیبی؛ پارلمان رو وادار کرد',
    },
    <String, dynamic>{
      'id': 'aligat', 'name': 'الیگات',
      'aliases': <String>['الیگیت', 'aligat', 'aligaat', 'aligator', 'alligat'],
      'lines': <String>['الیگات؛ شکارچی لحظه‌های حساس مسابقه!'],
    },
    <String, dynamic>{
      'id': 'niusha', 'name': 'نیوشا',
      'aliases': <String>['نیوشه', 'niusha', 'niousha', 'nyusha', 'newsha'],
      'lines': <String>['نیوشا؛ یکی از شخصیت‌های مرموز دنیای گل‌کوچیک!'],
    },
    <String, dynamic>{
      'id': 'sahargoli', 'name': 'سهرگلی',
      'aliases': <String>['سحرگلی', 'sahargoli', 'sahar goli', 'sahrgoli'],
      'lines': <String>['سهرگلی؛ متخصص اتفاقات غیرمنتظره!'],
    },
    <String, dynamic>{
      'id': 'aref', 'name': 'عارف',
      'aliases': <String>['aref', 'aaref', 'arefe'],
      'lines': <String>['عارف؛ مردی که همیشه یک نقشه مخفی دارد!'],
    },
    <String, dynamic>{
      'id': 'amir_afsaneha', 'name': 'امیرافسانه‌ها', 'fixed': true,
      'aliases': <String>['امیر افسانه ها', 'امیر افسانه', 'امیرافسانه', 'amir afsaneha', 'amirafsaneha', 'amir afsane'],
      'lines': <String>['مردی که سلطان شکست عشقی داخل گل‌کوچیک بوده و هست!'],
      'traits': 'سلطان شکست عشقی داخل گل‌کوچیک',
    },
    <String, dynamic>{
      'id': 'leila_lor', 'name': 'لیلا لور',
      'aliases': <String>['لیلالور', 'leila lor', 'leyla lor', 'laila lor', 'lila lor'],
      'lines': <String>['لیلا لور؛ افسانه‌ای با داستان‌های تمام‌نشدنی!'],
    },
    <String, dynamic>{
      'id': 'ahmad_rishsefid', 'name': 'احمد ریش‌سفید', 'fixed': true,
      'aliases': <String>['احمد ریش سفید', 'ریش سفید', 'ahmad rish sefid', 'rish sefid', 'ahmad'],
      'lines': <String>['بابانوئل زمانه؛ کسی که قراره شب کریسمس برامون کادو بیاره!'],
      'traits': 'بابانوئل زمانه',
    },
    <String, dynamic>{
      'id': 'arash_sibil', 'name': 'آرش سیبیل', 'fixed': true,
      'aliases': <String>['ارش سیبیل', 'ارش سبیل', 'آرش سبیل', 'arash sibil', 'arash sebil', 'sibil'],
      'lines': <String>['پدر دوم گل‌کوچیک؛ سلطان لوکیشن‌های نامنظم!'],
      'traits': 'پدر دوم گل‌کوچیک؛ سلطان لوکیشن‌های نامنظم',
    },
    <String, dynamic>{
      'id': 'arash_perfect', 'name': 'آرش پرفکت',
      'aliases': <String>['ارش پرفکت', 'arash perfect', 'arash perfekt'],
      'lines': <String>['آرش پرفکت؛ اسمش پرفکته، بقیه‌ش رو باید خودش ثابت کنه!'],
    },
    <String, dynamic>{
      'id': 'arefe', 'name': 'عارفه',
      'aliases': <String>['arefe', 'arefeh', 'aarefe'],
      'lines': <String>['عارفه؛ ستاره‌ای که قوانین خودش را دارد!'],
    },
    <String, dynamic>{
      'id': 'arisha', 'name': 'آریشا',
      'aliases': <String>['اریشا', 'arisha', 'aarisha', 'areesha'],
      'lines': <String>['آریشا؛ بازیکنی که هیچ‌وقت قابل پیش‌بینی نیست!'],
    },
    <String, dynamic>{
      'id': 'captain_farshid', 'name': 'کاپیتان فرشید', 'fixed': true,
      'aliases': <String>['کاپیتان', 'فرشید', 'captain farshid', 'kapitan farshid', 'farshid'],
      'lines': <String>['کسی که جایگزین ناصرالدین‌شاه شد!'],
      'traits': 'جایگزین ناصرالدین‌شاه',
    },
    <String, dynamic>{
      'id': 'fatemeh', 'name': 'فاطمه',
      'aliases': <String>['fatemeh', 'fateme', 'fatima', 'fatemah'],
      'lines': <String>['فاطمه؛ شخصیت ویژه و غیرقابل‌جایگزین!'],
    },
    <String, dynamic>{
      'id': 'nader_ajal', 'name': 'نادر اجل',
      'aliases': <String>['نادراجل', 'nader ajal', 'nader ajl', 'nadir ajal', 'ajal'],
      'lines': <String>['نادر اجل؛ متخصص لحظه‌های عجیب بازی!'],
    },
    <String, dynamic>{
      'id': 'setareh', 'name': 'ستاره',
      'aliases': <String>['setareh', 'setare', 'setara'],
      'lines': <String>['ستاره؛ نامش خودش همه‌چیز را توضیح می‌دهد!'],
    },
    <String, dynamic>{
      'id': 'baziyashar', 'name': 'بازیاشار',
      'aliases': <String>['بازی اشار', 'باز یاشار', 'baziyashar', 'bazi yashar', 'baziashar', 'yashar'],
      'lines': <String>['بازیاشار؛ متخصص غافلگیرکردن رقبا!'],
    },
    <String, dynamic>{
      'id': 'ro_infantino', 'name': 'رو اینفانتینو',
      'aliases': <String>['اینفانتینو', 'رواینفانتینو', 'ro infantino', 'infantino', 'roo infantino'],
      'lines': <String>['رو اینفانتینو؛ رئیس تشریفات مسابقات گل‌کوچیک!'],
    },
    <String, dynamic>{
      'id': 'saeed', 'name': 'سعید',
      'aliases': <String>['saeed', 'saeid', 'saied'],
      'lines': <String>['سعید؛ بازیکنی با هزار داستان و یک عالمه حاشیه!'],
    },
    <String, dynamic>{
      'id': 'fidel', 'name': 'فیدل',
      'aliases': <String>['fidel', 'fidl', 'fydel'],
      'lines': <String>['فیدل؛ شخصیت خاص دنیای رقابت!'],
    },
    <String, dynamic>{
      'id': 'mahsa', 'name': 'محصا',
      'aliases': <String>['مهسا', 'mahsa', 'mahssa'],
      'lines': <String>['محصا؛ هنوز خود اوراکل هم در حال کشف رازهاشه!'],
    },
    <String, dynamic>{
      'id': 'noor', 'name': 'نور',
      'aliases': <String>['noor', 'nour', 'nur'],
      'lines': <String>['نور؛ روشنایی دنیای گل‌کوچیک!'],
    },
    <String, dynamic>{
      'id': 'leila_noor', 'name': 'لیلا نور',
      'aliases': <String>['لیلانور', 'leila noor', 'leyla noor', 'laila noor', 'leila nour'],
      'lines': <String>['لیلا نور؛ ستاره‌ای در میان ستاره‌ها!'],
    },
    <String, dynamic>{
      'id': 'amir_noor', 'name': 'امیر نور',
      'aliases': <String>['امیرنور', 'amir noor', 'amir nour', 'amirnoor'],
      'lines': <String>['امیر نور؛ مردی با نامی درخشان و حضوری متفاوت!'],
    },
    <String, dynamic>{
      'id': 'yahya', 'name': 'یحیا',
      'aliases': <String>['یحیی', 'yahya', 'yahia', 'yahyaa'],
      'lines': <String>['یحیا؛ مردی که همیشه آماده یک چالش جدیده!'],
    },
    <String, dynamic>{
      'id': 'ali_god', 'name': 'علی‌گاد', 'fixed': true,
      'aliases': <String>['علی گاد', 'علیگاد', 'ali god', 'aligod', 'ali gad', 'ali good'],
      'lines': <String>['علی‌گاد و آرش سیبیل؛ سلطان سیبیل‌های مطلق اپلیکیشن!'],
      'traits': 'با آرش سیبیل سلطان سیبیل‌های مطلق اپلیکیشن',
    },
  ],
  // Login greetings: 3-step mix-up joke ("is that Original?"). Never claims Original actually logged in.
  'login_greetings': <List<String>>[
    <String>['{jan} اورجینال رو بگیر!', 'اِه! تو که اورجینال نیستی!', 'ببخشید، فکر کردم سلطان تله‌ها برگشته!'],
    <String>['اورجینال! خودتی؟ بالاخره برگشتی؟', 'وایسا ببینم... نه بابا، اشتباه گرفتم!', 'تو کجا و اورجینال کجا!'],
    <String>['{jan} تله رو بگیر اورجینال!', 'اِ اِ اِ! این قیافه آشنا نیست!', 'بازیکن جدید داریم یا اورجینال تغییر چهره داده؟'],
    <String>['به‌به! اورجینال افسانه‌ای!', 'صبر کن... اسم تو که اورجینال نیست!', 'سیستمم هنوز تو خاطراتشه!'],
    <String>['{jan} اورجینال رو بگیر!', 'اه، تویی؟!', 'ببخشید، داشتم منتظر صاحب اصلی این بازی می‌موندم!'],
  ],
  // When the logged-in player really is Original.
  'login_self_original': <List<String>>[
    <String>['{jan} اورجینال رو بگیر!', 'این دفعه واقعاً خودتی! سلطان تله‌ها برگشت!'],
    <String>['اورجینال! خودتی؟', 'آره خودشه! تله‌ها رو آماده کنید!'],
  ],
  // Plain greetings with the real display name ({name}); used when the mix-up joke is not chosen.
  'login_plain': <String>[
    'سلام {name}! خوش برگشتی!',
    '{jan} {name} اومد! بزن بریم!',
    '{name}! دلم برای بازی‌هات تنگ شده بود... یه کوچولو!',
  ],
  'spontaneous': <String, dynamic>{
    'enter': <String>['ای بابا! حوصله‌مون سر رفت، اورجینال هم نیست!', '{jan} اینجا چه خبره؟'],
    'waiting': <String>['دو تا تله به کار ببر، حداقل یه خنده‌ای بکنیم!', 'منتظر چی هستیم؟ یه بازی بزن دیگه!'],
    'match': <String>['{jan} تله رو بگیر!', 'بزن بریم قهرمان!'],
    'idle': <String>['الوووو! کسی زنده‌ست اینجا؟', 'تو یخ زدی یا گوشیت؟'],
    'funny': <String>['من دیگه حرفی ندارم!', 'من یه ربات کوچولوام... ولی خیلی باهوش‌تر از اونی‌ام که فکر می‌کنی!'],
    'unexpected': <String>['صبر کن ببینم! این دیگه چه حرکتی بود؟'],
    'tease': <String>['{jan} اینجا چه خبره؟', 'اینقدر به من زل نزن، خجالت می‌کشم!'],
  },
  'results': <String, dynamic>{
    'lose': <String>[
      'هاهاهاها! این بود تمام توانت؟',
      'نه بابا! این دیگه چه نمایشی بود؟',
      'اوراکل شاهد یک فاجعه تاریخی بود!',
      'دفعه بعد شاید تونستی!',
      '{jan} این یکی رو دیگه چطوری توضیح بدیم؟',
    ],
    'win': <String>[
      'اووووه! این شد یه چیزی!',
      'آفرین قهرمان! ترکوندی!',
      'این حرکت رو باید قاب گرفت!',
      'بالاخره یه بازی درست‌وحسابی دیدیم!',
    ],
    'bad': <String>['داداش تمرکز کن! توپ اون طرفه!', 'یه نفس عمیق بکش، هنوز امید هست!'],
    'great': <String>[
      '{jan} {score}! این دیگه برد نبود، کنسرت بود! به همه بگو مربیت من بودم!',
      'اووووووه! {score}؟! حریف هنوز داره دنبال توپ می‌گرده!',
    ],
    'draw': <String>['مساوی؟ یعنی هردوتون به یه اندازه خوب... یا بد!', 'نه بردی نه باختی، مثل چایی ولرم!'],
  },
  // Funny tutorials — each `how` explains the REAL controls/mechanics of that game in NEXORA.
  'tutorials': <String, dynamic>{
    'finger_soccer': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'شوت زدن',
        'line': '{jan} مهره‌ی خودتو بکش عقب و ول کن!',
        'how': 'یکی از مهره‌های خودت رو بکش و رها کن؛ هرچی بیشتر بکشی ضربه محکم‌تره. وقتی همه‌چی ایستاد نوبت عوض می‌شه.',
      },
      <String, dynamic>{
        'id': 'ice', 'title': 'ضربات یخی',
        'line': 'ضربات یخی فرم بزن!\nسرد و حساب‌شده، بذار دروازه‌بان یخ بزنه!',
        'how': 'کم بکش تا ضربه آروم و دقیق باشه؛ مهره رو آروم به توپ برسون و زاویه رو با جهت کشیدن تنظیم کن.',
      },
      <String, dynamic>{
        'id': 'power', 'title': 'ضربات قدرتی',
        'line': 'بمیره دلی که بترسد!\nبزن بره!',
        'how': 'تا آخر بکش تا ضربه‌ی کامل بزنی؛ ولی حواست باشه بعد از شوت محکم، مهره‌ها خیلی جابه‌جا می‌شن.',
      },
      <String, dynamic>{
        'id': 'fast', 'title': 'ضربات سریع',
        'line': 'معطل نکن قهرمان!\nقبل از اینکه دفاع بفهمه چی شد، شلیک کن!',
        'how': 'تو بازی آنلاین هر نوبت ۱۵ ثانیه‌ست؛ زود تصمیم بگیر. گل مستقیم از ضربه‌ی شروع حساب نمی‌شه.',
      },
      <String, dynamic>{
        'id': 'golden', 'title': 'گل طلایی',
        'line': 'مساوی شد؟ آروم! گل طلایی داریم، هرکی زودتر بزنه شاهه!',
        'how': 'هر بازی ۵ دقیقه‌ست و تو تساوی، اولین گل (گل طلایی) برنده رو مشخص می‌کنه.',
      },
    ],
    'carrom': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'استرایکر',
        'line': 'استرایکر رو بذار رو خط و نشونه بگیر، این‌جا جای لرزیدن نیست!',
        'how': 'استرایکر رو روی خط پایه جابه‌جا کن، نشونه بگیر و ضربه بزن. انداختن مهره‌ی خودت یعنی نوبت دوباره.',
      },
      <String, dynamic>{
        'id': 'queen', 'title': 'ملکه',
        'line': 'ملکه قرمزه رو انداختی؟ زود بپوشونش وگرنه برمی‌گرده سر جاش!',
        'how': 'بعد از انداختن ملکه باید همون موقع یکی از مهره‌های خودت رو هم بندازی (پوشش). انداختن استرایکر خطاست.',
      },
    ],
    'billiards': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'بریک و گروه',
        'line': 'اولین توپی که بندازی گروهت رو تعیین می‌کنه؛ پس با کلاس بنداز!',
        'how': 'بعد از بریک، اولین توپی که بندازی (ساده یا راه‌راه) گروه تو می‌شه. همه‌ی گروهت رو بنداز، بعد توپ ۸.',
      },
      <String, dynamic>{
        'id': 'foul', 'title': 'خطا',
        'line': 'توپ سفید رو ننداز تو سوراخ، اون که مهمون نیست!',
        'how': 'افتادن سفید یا اول زدن به توپ اشتباه = توپ در دست حریف. توپ ۸ زودتر از موعد یا همراه سفید = باخت.',
      },
    ],
    'backgammon': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'تاس و حرکت',
        'line': 'تاس بنداز و مهره‌ها رو ببر جلو؛ جفت آوردی؟ {jan} چهار حرکت داری!',
        'how': 'به اندازه‌ی هر تاس یه مهره جلو ببر؛ جفت یعنی چهار حرکت. مهره‌ی تنها رو می‌شه زد و فرستاد بار.',
      },
      <String, dynamic>{
        'id': 'bear', 'title': 'برداشتن',
        'line': 'همه رسیدن خونه؟ حالا شروع کن به جمع کردن، مثل مهمونی آخر شب!',
        'how': 'وقتی همه‌ی مهره‌ها تو خونه‌ی خودتن، شروع کن به برداشتن. اول کسی که همه رو برداره برنده‌ست.',
      },
    ],
    'ludo': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'شش بیار',
        'line': 'شش نیاری از خونه بیرون نمیای، مثل من صبح‌های شنبه!',
        'how': 'با ۶ مهره از پایگاه بیرون میاد و یه نوبت اضافه داری (سه تا ۶ پشت هم نوبت رو می‌سوزونه). خونه‌های ستاره‌دار امنن.',
      },
    ],
    'snakes_ladders': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'مار و پله',
        'line': 'پله رو دیدی برو بالا، مار رو دیدی... خب، خداحافظ!',
        'how': 'تاس بنداز و جلو برو؛ پای پل نور بالا می‌ری و رو سر مار پایین. برای ۱۰۰ عدد دقیق لازمه؛ ۶ یعنی نوبت دوباره.',
      },
    ],
    'uno': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'NX!',
        'line': 'یه کارت موند؟ داد بزن NX! وگرنه دو تا کارت جریمه هدیه می‌گیری!',
        'how': 'کارتی بازی کن که رنگ، عدد یا نمادش با کارت وسط یکی باشه. با یه کارت باقی‌مونده دکمه‌ی NX! رو بزن.',
      },
    ],
    'quiz': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'سرعت',
        'line': 'زود جواب بده، ساعت با کسی شوخی نداره... جز من!',
        'how': '۱۰ سؤال، هر کدوم ۱۵ ثانیه. جواب درست امتیاز داره و سرعت جایزه‌ی اضافه.',
      },
    ],
    'mafia': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'basic', 'title': 'مافیا',
        'line': 'شب‌ها چشمات بسته، روزها زبونت باز! مافیا رو پیدا کن!',
        'how': 'شهروندها باید مافیا رو پیدا کنن؛ مافیا شب‌ها یه نفر رو حذف می‌کنه. پزشک نجات می‌ده، کارآگاه استعلام می‌گیره. روزها بحث و رأی‌گیری.',
      },
    ],
  },
  // First-run guided tour, per section. target: 'key:<id>' (an OracleTourTarget in the UI) or 'area:top|center|bottom'
  // (or null for a centred card). Shown once per section per account; replayable from Settings.
  'tours': <String, dynamic>{
    'home': <Map<String, dynamic>>[
      <String, dynamic>{'target': null, 'title': 'خوش اومدی به NEXORA!', 'text': '{jan} من اوراکلم، راهنمای شیطون این‌جا! بیا یه دور سریع بزنیم که گم نشی.'},
      <String, dynamic>{'target': 'area:top', 'title': 'بالای صفحه', 'text': 'این بالا اسم و سطح و سکه‌هاته. سکه‌ها رو با بازی و جایزه‌ی روزانه جمع می‌کنی، نه با گریه!'},
      <String, dynamic>{'target': 'key:dock', 'title': 'داک پایین', 'text': 'این نوار پایین راه همه‌جاست: چت و رسانه، اوراکل، فروشگاه، تورنمنت و جایزه‌ها.'},
      <String, dynamic>{'target': 'key:dock.games', 'title': 'دکمه‌ی بزرگ بازی', 'text': 'این دکمه‌ی گنده‌ی وسط، اتاق‌ها و بازی‌هاست. {jan} از این‌جا می‌ری تو دل ماجرا!'},
    ],
    'dock': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'key:dock.social', 'title': 'چت و رسانه', 'text': 'پست و استوری، پیام‌ها و دوستات این‌جان.'},
      <String, dynamic>{'target': 'key:dock.oracle', 'title': 'اوراکل', 'text': 'این خودمم! هر سؤالی داشتی بپرس، حتی سؤالای عجیب.'},
      <String, dynamic>{'target': 'key:dock.shop', 'title': 'فروشگاه', 'text': 'با سکه‌هات لباس آواتار، مهره، استرایکر، چوب بیلیارد، تم و قاب بخر. خرج نکنی سکه‌ها کپک می‌زنن!'},
      <String, dynamic>{'target': 'key:dock.tournaments', 'title': 'تورنمنت', 'text': 'جام‌ها این‌جان: ثبت‌نام کن، بازی کن، جایزه ببر.'},
      <String, dynamic>{'target': 'key:dock.rewards', 'title': 'جایزه و پک', 'text': 'جایزه‌ی روزانه و پک‌ها این‌جاست. هر روز سر بزن، من حواسم هست!'},
    ],
    'rooms': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'اتاق‌ها', 'text': '{jan} این‌جا مرکز بازی آنلاینه: «بازی سریع» تو رو با یه حریف جفت می‌کنه، «ساخت اتاق» یه اتاق با کد می‌سازه.'},
      <String, dynamic>{'target': 'area:center', 'title': 'اتاق‌های باز', 'text': 'اتاق‌های زنده و باز رو این‌جا می‌بینی؛ بزن روش و برو تو. کد داری؟ با کد هم می‌شه وارد شد.'},
      <String, dynamic>{'target': 'area:bottom', 'title': 'همه‌ی بازی‌ها', 'text': 'می‌خوای اول با ربات تمرین کنی؟ «همه‌ی بازی‌ها» رو بزن، آفلاین هم کار می‌کنه.'},
    ],
    'games': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:center', 'title': 'فهرست بازی‌ها', 'text': 'گل‌کوچیک، کارم، بیلیارد، تخته، لودو، مار و پله، کارت، کوییز و مافیا! یکی رو انتخاب کن تا بری صفحه‌ی تنظیماتش.'},
    ],
    'game_setup': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'لابی بازی', 'text': 'این صفحه‌ی آماده‌شدنه: حالت بازی رو انتخاب کن — با بات، دو نفره روی یه گوشی، یا آنلاین.'},
      <String, dynamic>{'target': 'area:center', 'title': 'سختی و قوانین', 'text': 'سختی بات و تعداد بازیکن رو این‌جا تنظیم کن. قوانین هم همین‌جاست؛ نخونی من می‌خونم برات!'},
      <String, dynamic>{'target': 'area:bottom', 'title': 'شروع', 'text': '{jan} دکمه‌ی شروع یا «ورود به لابی آنلاین» رو بزن و بترکون!'},
    ],
    'tournaments': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'جام‌های نکسورا', 'text': 'تب‌ها: ثبت‌نام، به‌زودی، زنده، تمام‌شده و مال من. هر جامی که ثبت‌نامش بازه رو ببین.'},
      <String, dynamic>{'target': 'area:center', 'title': 'ثبت‌نام و کد دعوت', 'text': 'روی جام بزن تا جزئیات، جایزه‌ها و جدول رو ببینی. جام خصوصی؟ با «کد دعوت» وارد شو.'},
      <String, dynamic>{'target': 'area:bottom', 'title': 'اعلان‌ها', 'text': '۱۰ دقیقه قبل از شروع خبرت می‌کنم که چک‌این کنی. {jan} دیر کنی، قرعه بی‌تو کشیده می‌شه!'},
    ],
    'shop': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'فروشگاه', 'text': 'دسته‌ها: پوشش آواتار، دکور، مهره‌ی فوتبال، استرایکر کارم، چوب بیلیارد، تم، قاب و نشان.'},
      <String, dynamic>{'target': 'area:center', 'title': 'کمیابی', 'text': 'رنگ کارت‌ها یعنی کمیابی: معمولی، کمیاب، حماسی، افسانه‌ای. خرید با سکه‌ست و قیمت رو سرور چک می‌کنه، پس تقلب ممنوع!'},
    ],
    'social': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'چت و رسانه', 'text': 'سه بخش داره: پست و استوری، پیام‌ها، دوستان.'},
      <String, dynamic>{'target': 'area:center', 'title': 'پست و استوری', 'text': 'عکس بذار، لایک و کامنت کن، استوری ۲۴ ساعته بذار. {jan} فقط عکس سلفی صبح زود نذار!'},
    ],
    'chat': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'گفت‌وگوها', 'text': 'تب‌ها: گفت‌وگوها، تماس‌ها و مخاطبان. چت خصوصی، گروه و کانال بساز.'},
      <String, dynamic>{'target': 'area:center', 'title': 'تماس صوتی و تصویری', 'text': 'تو هر چت می‌تونی تماس صوتی یا تصویری بگیری و دعوت بازی بفرستی.'},
    ],
    'profile': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'پروفایل', 'text': 'این مدار شخصی توئه: هویت، مأموریت‌ها، کمد لباس، فضای من، دستاوردها و آمار.'},
      <String, dynamic>{'target': 'area:center', 'title': 'آمار و دستاورد', 'text': 'آمار واقعی بازی‌هات این‌جاست. من فقط با همین آمار سربه‌سرت می‌ذارم، چیزی از خودم درنمیارم!'},
    ],
    'settings': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'تنظیمات', 'text': 'صدا و موسیقی، کیفیت گرافیک، کاهش حرکت و لرزش این‌جاست.'},
      <String, dynamic>{'target': 'area:center', 'title': 'اوراکل شیطون', 'text': 'اگه از دستم خسته شدی می‌تونی منو این‌جا خاموش کنی... ولی دلت میاد؟ تور منو هم از همین‌جا دوباره ببین.'},
    ],
    'oracle': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:bottom', 'title': 'گفت‌وگو با اوراکل', 'text': '{jan} این‌جا هرچی بخوای بپرس: قوانین، آمار، پیشنهاد بازی، یا درباره‌ی بچه‌های گل‌کوچیک!'},
    ],
    'admin': <Map<String, dynamic>>[
      <String, dynamic>{'target': 'area:top', 'title': 'پنل مدیریت', 'text': 'این‌جا فقط دست مدیرهاست. هر بخش فقط با دسترسی خودش باز می‌شه و همه‌ی کارها ثبت می‌شن.'},
    ],
  },
  // "{jan}" replies for common requests (patterns are normalised; ZWNJ/spacing/letter variants handled).
  'jan_replies': <Map<String, dynamic>>[
    <String, dynamic>{'patterns': <String>['گل کوچیک', 'گلکوچیک', 'فوتبال انگشتی', 'gol kochik'], 'reply': '{jan} گل‌کوچیکو بگیر!'},
    <String, dynamic>{'patterns': <String>['بریم مسابقه', 'مسابقه بدیم', 'بریم بازی کنیم'], 'reply': '{jan} بزن بریم قهرمان!'},
    <String, dynamic>{'patterns': <String>['نظرت چیه', 'نظرت چیست'], 'reply': '{jan} چی رو می‌خوای بدونی؟'},
    <String, dynamic>{'patterns': <String>['بریم تمرین', 'تمرین کنیم'], 'reply': '{jan} تمرین رو بترکون!'},
    <String, dynamic>{'patterns': <String>['چیکار کنم', 'چی کار کنم', 'چکار کنم'], 'reply': '{jan} اول یه تله درست‌وحسابی بگیر!'},
    <String, dynamic>{'patterns': <String>['بازی شروع کنیم', 'شروع کنیم'], 'reply': '{jan} توپ رو بنداز وسط!'},
  ],
  // Bare calls that get only "{jan}؟" (ORACLE waits).
  'wake_words': <String>['اوراکل', 'اوراکله', 'oracle', 'orakel', 'orakl', 'هی اوراکل', 'هوی', 'هی'],
};
