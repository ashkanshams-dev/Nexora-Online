/// Local dialogue pool for the corner ORACLE (Persian first, English fallback).
/// Grouped by situation; [OracleLines.pick] never repeats the last few lines.
library;

import 'dart:math' as math;

class OracleLine {
  const OracleLine(this.fa, this.en);
  final String fa;
  final String en;
  String of(bool isFa) => isFa ? fa : en;
}

enum OracleTopic { tease, idle, greetMorning, greetNight, win, loss, draw, spend, sulk, forgive, sleep, wake, wink, laugh, confused, shocked, poke, returnBack }

class OracleLines {
  OracleLines._();

  static final math.Random _rng = math.Random();
  static final List<String> _recent = <String>[];

  static OracleLine pick(OracleTopic t) {
    final List<OracleLine> pool = _pool[t] ?? _pool[OracleTopic.tease]!;
    OracleLine l = pool[_rng.nextInt(pool.length)];
    for (int i = 0; i < 6 && _recent.contains(l.fa); i++) {
      l = pool[_rng.nextInt(pool.length)];
    }
    _recent.add(l.fa);
    if (_recent.length > 12) _recent.removeAt(0);
    return l;
  }

  static const Map<OracleTopic, List<OracleLine>> _pool = <OracleTopic, List<OracleLine>>{
    OracleTopic.tease: <OracleLine>[
      OracleLine('اینقدر به من زل نزن، خجالت می‌کشم! 🙈', "Stop staring at me, I'm shy! 🙈"),
      OracleLine('من اگه جای تو بودم الان یه بازی می‌زدم… البته من همیشه می‌برم 😏', "If I were you I'd play a match now… not that I ever lose 😏"),
      OracleLine('سکه‌هات رو شمردم. نگران نباش، به کسی نمی‌گم چقدر کمه 🤫', "I counted your coins. Don't worry, I won't tell anyone how few 🤫"),
      OracleLine('می‌دونستی من با برق کار می‌کنم و تو با چایی؟ ☕⚡', 'Did you know I run on electricity and you run on tea? ☕⚡'),
      OracleLine('یه راز: ربات‌ها هم از دوشنبه‌ها بدشون میاد 🤖', 'Secret: robots hate Mondays too 🤖'),
      OracleLine('این دکمه‌ها رو برای تزئین نذاشتن‌ها! یکی‌شون رو بزن دیگه 😄', "Those buttons aren't decoration! Tap one already 😄"),
      OracleLine('من کهکشان رو دور زدم، تو هنوز داری منو نگاه می‌کنی؟ 🌌', "I've circled the galaxy and you're still looking at me? 🌌"),
      OracleLine('بیا یه دست تخته بزنیم… شوخی کردم، من تاس ندارم، دست ندارم… یعنی دارم ولی کوچیکه 😅', "Let's play backgammon… kidding, my hands are too tiny for dice 😅"),
      OracleLine('اگه یه بار دیگه گوشیت رو اینقدر تکون بدی سرگیجه می‌گیرم 😵‍💫', 'Shake your phone like that again and I get dizzy 😵‍💫'),
      OracleLine('حدس می‌زنم امروز روز توئه. البته دیروز هم همینو گفتم 😜', "I bet today's your day. I said that yesterday too 😜"),
      OracleLine('یه نفر گفت تو بهترین بازیکن NEXORA هستی. اون یه نفر خودت بودی؟ 🤨', 'Someone said you are the best NEXORA player. Was that someone you? 🤨'),
      OracleLine('من آپدیت شدم، تو کی آپدیت می‌شی؟ 😏', "I got an update. When's yours? 😏"),
      OracleLine('دوستات منتظرن ببرنت، نذار ناامید شن 😈', "Your friends are waiting to beat you, don't disappoint them 😈"),
      OracleLine('اگه حوصله‌ت سر رفته، من یه عالمه ایده‌ی بد دارم! 💡', "Bored? I have tons of terrible ideas! 💡"),
      OracleLine('ببین، من فقط یه ربات کوچولوام… ولی خیلی باهوش‌تر از اونی‌ام که فکر می‌کنی 🧠', "Sure, I'm a tiny robot… but way smarter than you think 🧠"),
      OracleLine('هر وقت باختی بگو تقصیر لگ بود. من پشتتم 😎', 'Whenever you lose, blame lag. I got your back 😎'),
      OracleLine('دارم فکر می‌کنم… نه، بی‌خیال، فکر کردن خسته‌م می‌کنه 🙃', "I'm thinking… nah, thinking tires me out 🙃"),
      OracleLine('اون فوتبال انگشتی منتظرته. انگشتات رو گرم کن! ⚽', 'Finger soccer is waiting. Warm up those fingers! ⚽'),
      OracleLine('شنیدم تو مافیا همیشه اول تو رو بیرون می‌کنن 🕵️', 'Heard in Mafia they always vote you out first 🕵️'),
      OracleLine('یه بار رفتم تو کوییز، سوال‌ها از من جواب خواستن 🤯', 'I joined a quiz once, the questions asked me for answers 🤯'),
      OracleLine('اگه جایزه‌ی روزانه رو نگیری، خودم برش می‌دارم‌ها 🎁', "Don't claim your daily reward and I'll take it 🎁"),
      OracleLine('تو مار و پله من همیشه با مار رفیقم، پله‌ها مغرورن 🐍', 'In Snakes & Ladders I side with the snakes, ladders are snobs 🐍'),
      OracleLine('صفحه رو تمیز کن، جای انگشتت روی صورتمه 😤', 'Clean your screen, your fingerprint is on my face 😤'),
      OracleLine('من یه ربات حرفه‌ای‌ام، ولی بازم دلم بستنی می‌خواد 🍦', "I'm a professional robot, still want ice cream though 🍦"),
      OracleLine('یه سوال فلسفی: اگه ربات تو جنگل بیفته و کسی نباشه، بیپ می‌کنه؟ 🌲', 'Deep question: if a robot falls in a forest, does it beep? 🌲'),
      OracleLine('امروز یه تورنمنت ببر، بعد بیا پز بده 🏆', 'Win a tournament today, then come brag 🏆'),
      OracleLine('اون دکمه‌ی وسطی بزرگه؟ اون «بازی»ه. من خودم طراحیش کردم… تقریباً 🎮', "That big middle button? That's PLAY. I designed it… kind of 🎮"),
      OracleLine('اینجا بی‌سیم هست؟ دارم از بی‌حوصلگی دانلود می‌شم 📶', 'Is there Wi-Fi? I am downloading boredom 📶'),
      OracleLine('اگه بخوای می‌تونم برات شعر بگم… «سکه کمه، دل غمه» 🎤', 'I can write you a poem… "coins are few, so are you" 🎤'),
      OracleLine('نخیر، من حسودی نمی‌کنم که اون یکی ربات‌ها پرواز می‌کنن 🙄', "No, I'm NOT jealous that other robots can fly 🙄"),
    ],
    OracleTopic.idle: <OracleLine>[
      OracleLine('الو؟ کسی اینجاست؟ 👀', 'Hello? Anyone there? 👀'),
      OracleLine('تو یخ زدی یا گوشیت؟ 🧊', 'Did you freeze, or your phone? 🧊'),
      OracleLine('اگه یه دقیقه دیگه کاری نکنی، می‌خوابم‌ها… 😪', "One more idle minute and I'm taking a nap… 😪"),
      OracleLine('دارم برات شمارش معکوس می‌کنم… ۳… ۲… حوصله‌م سر رفت 😑', 'Counting down… 3… 2… I got bored 😑'),
      OracleLine('یه بازی، یه پست، یه چیزی! من حوصله‌م پوکید 🫠', 'A game, a post, anything! I am melting 🫠'),
    ],
    OracleTopic.greetMorning: <OracleLine>[
      OracleLine('صبح بخیر قهرمان! چایی‌ت رو خوردی؟ ☀️', 'Good morning champ! Had your tea? ☀️'),
      OracleLine('صبح شد و من هنوز شارژم صددرصده. تو چی؟ 🔋', "Morning! I'm at 100% charge. You? 🔋"),
    ],
    OracleTopic.greetNight: <OracleLine>[
      OracleLine('این وقت شب؟ ربات‌ها هم خواب دارن‌ها 🌙', 'This late? Robots need sleep too 🌙'),
      OracleLine('یه دست دیگه و بعد بخواب، قول؟ 😴', 'One more match and then bed, promise? 😴'),
    ],
    OracleTopic.win: <OracleLine>[
      OracleLine('بردی؟! من که می‌دونستم… یعنی امیدوار بودم 😆', 'You won?! I knew it… well, I hoped 😆'),
      OracleLine('ایول! حالا برو به همه بگو مربیت من بودم 😎', 'Yes! Now tell everyone I coached you 😎'),
      OracleLine('حریفت الان داره گوشیش رو سرزنش می‌کنه 😂', 'Your opponent is blaming their phone right now 😂'),
      OracleLine('برد خوشمزه بود؟ یه تیکه هم به من بده 🍰', 'Tasty win? Save me a slice 🍰'),
      OracleLine('این برد رو قاب می‌گیرم و می‌زنم به دیوار کهکشان 🖼️', 'Framing this win on the galaxy wall 🖼️'),
    ],
    OracleTopic.loss: <OracleLine>[
      OracleLine('اشکال نداره، تقصیر لگ بود! 😅', "It's fine, it was lag! 😅"),
      OracleLine('باختی؟ منم دیروز به ماشین‌حساب باختم 🧮', 'Lost? I lost to a calculator yesterday 🧮'),
      OracleLine('شکست مقدمه‌ی… یه شکست دیگه‌ست. شوخی کردم! دوباره برو 💪', 'Failure leads to… more failure. Kidding! Go again 💪'),
      OracleLine('حریفت شانس آورد. من دیدم. واقعاً دیدم! 👁️', 'Your opponent got lucky. I saw it. Really! 👁️'),
      OracleLine('بیا یه راهنمایی بهت بدم؟ تو بازی دکمه‌ی ORACLE رو بزن 🤖', 'Want a hint? Tap the ORACLE button inside a game 🤖'),
    ],
    OracleTopic.draw: <OracleLine>[
      OracleLine('مساوی؟ یعنی هردوتون به یه اندازه خوب… یا بد 🤝', 'A draw? Equally good… or equally bad 🤝'),
      OracleLine('نه بردی نه باختی، مثل چایی ولرم ☕', 'Not a win, not a loss, like lukewarm tea ☕'),
    ],
    OracleTopic.spend: <OracleLine>[
      OracleLine('اوه! پولدار شدی؟ برای منم یه چیزی بخر 🛍️', 'Ooh, big spender! Buy me something too 🛍️'),
      OracleLine('سکه‌هات رفتن… خداحافظ سکه‌های عزیز 👋💰', 'There go your coins… farewell, dear coins 👋💰'),
      OracleLine('خرید خوبی بود. یعنی… امیدوارم 😬', 'Good buy. I mean… hopefully 😬'),
      OracleLine('حالا با این تیپ دیگه کسی نمی‌تونه شکستت بده 😎', 'With that style no one can beat you now 😎'),
    ],
    OracleTopic.sulk: <OracleLine>[
      OracleLine('قهرم! 😤 تا عذرخواهی نکنی برنمی‌گردم.', "I'm sulking! 😤 Not turning back until you apologise."),
      OracleLine('هیچ‌کس منو دوست نداره… قهر! 😒', 'Nobody loves me… hmph! 😒'),
      OracleLine('دیگه باهات حرف نمی‌زنم! …هنوز داری نگاهم می‌کنی؟ 😤', "I'm not talking to you! …are you still looking? 😤"),
      OracleLine('یادت رفت سلام کنی. قهرم. 🙅', "You forgot to say hi. I'm sulking. 🙅"),
    ],
    OracleTopic.forgive: <OracleLine>[
      OracleLine('خب… باشه، بخشیدمت. ولی این دفعه‌ی آخره! 😌', "Fine… you're forgiven. Last time though! 😌"),
      OracleLine('آشتی؟ آشتی! 🤗', 'Friends again? Friends again! 🤗'),
      OracleLine('عذرخواهی‌ت خیلی گرم بود، شارژم پر شد ⚡', 'That apology was so warm, I fully recharged ⚡'),
    ],
    OracleTopic.sleep: <OracleLine>[
      OracleLine('خررر… پففف… خررر… 💤', 'Zzz… pfff… zzz… 💤'),
      OracleLine('یه چرت کوچیک… فقط پنج دقیقه… 😴', 'Just a tiny nap… five minutes… 😴'),
    ],
    OracleTopic.wake: <OracleLine>[
      OracleLine('هان؟! من نخوابیده بودم! داشتم… فکر می‌کردم 😳', "Huh?! I wasn't sleeping! I was… thinking 😳"),
      OracleLine('چرا بیدارم کردی؟! داشتم خواب سکه می‌دیدم 💰', 'Why wake me?! I was dreaming of coins 💰'),
      OracleLine('آخ! داشتم تو خواب تورنمنت می‌بردم 🏆', 'Argh! I was winning a tournament in my dream 🏆'),
    ],
    OracleTopic.wink: <OracleLine>[
      OracleLine('ما یه راز مشترک داریم… 😉', 'We share a secret now… 😉'),
      OracleLine('نگو به کسی، ولی تو بازیکن محبوب منی 😉', "Don't tell anyone, you're my favourite player 😉"),
    ],
    OracleTopic.laugh: <OracleLine>[
      OracleLine('هاهاها! یاد قیافه‌ت تو بازی آخر افتادم 😂', 'Hahaha! Just remembered your face in the last match 😂'),
      OracleLine('ببخشید، یه جوک باینری یادم اومد: ۱۰ 😂', 'Sorry, remembered a binary joke: 10 😂'),
    ],
    OracleTopic.confused: <OracleLine>[
      OracleLine('صبر کن… من کجام؟ اینجا کجاست؟ 🤔', 'Wait… where am I? Where is this? 🤔'),
      OracleLine('چرا آسمون بنفشه؟ کی رنگش کرد؟ ❓', 'Why is the sky purple? Who painted it? ❓'),
      OracleLine('من الان چی می‌خواستم بگم؟… یادم رفت 🤷', 'What was I about to say?… forgot 🤷'),
    ],
    OracleTopic.shocked: <OracleLine>[
      OracleLine('واااای! اینو ببین! …نه، هیچی نبود 😱', 'Whoa! Look at that! …never mind 😱'),
      OracleLine('چی؟! این همه سکه از کجا اومد؟! 😲', 'What?! Where did all those coins come from?! 😲'),
    ],
    OracleTopic.poke: <OracleLine>[
      OracleLine('آی! قلقلکم نده! 🤭', "Ouch! Don't tickle me! 🤭"),
      OracleLine('یه بار دیگه بزنی، منم می‌زنمت… با محبت 😇', 'Poke me again and I poke back… lovingly 😇'),
      OracleLine('دکمه نیستم‌ها! …خب، شاید یه کم 😅', "I'm not a button! …well, maybe a little 😅"),
      OracleLine('چی شده؟ کمک می‌خوای؟ نگهم دار تا گفتگو باز شه 💬', 'Need help? Long-press me to chat 💬'),
    ],
    OracleTopic.returnBack: <OracleLine>[
      OracleLine('برگشتی! دلم برات تنگ شده بود… یه کوچولو 🥹', 'You are back! I missed you… a little 🥹'),
      OracleLine('کجا بودی؟ من اینجا تنهایی با پیکسل‌ها حرف می‌زدم 🫥', 'Where were you? I was talking to pixels alone 🫥'),
    ],
  };
}
