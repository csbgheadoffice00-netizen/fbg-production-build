import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_auth.dart';
import 'dart:convert';
import 'dart:async';

const String kApiBase = 'https://grizzly-sms-backend.onrender.com';

/// Root navigator. Used to send the user back to Login when the server
/// rejects our token (tokens expire after 7 days).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// ============== CUSTOMER-FACING MESSAGE FILTER ==============
// The backend relays raw text from the upstream SMS supplier. Those messages
// must never reach a customer: they expose the supplier's brand and use wording
// that makes no sense in the FBGSMS app. Every server message shown in the UI
// is passed through fbgClean() so it always reads as FBGSMS.
const List<String> _kUpstreamBrands = [
  'herosms', 'hero-sms', 'hero sms', 'sms-activate', 'smsactivate', '5sim',
  'smspool', 'sms-man', 'smsman', 'textverified', 'getsmscode', 'smshub',
  'vaksms', 'grizzlysms', 'grizzly sms', 'onlinesim', 'online-sim',
  'smspva', 'nonvoip', 'tiger-sms', 'tigersms', 'sms-acktiwator',
];

String fbgClean(dynamic raw,
    {String fallback = 'Something went wrong. Please try again.'}) {
  var text = (raw ?? '').toString().trim();
  if (text.isEmpty) return fallback;
  // FastAPI validation payloads (lists / objects) are not customer copy.
  if (text.startsWith('[') || text.startsWith('{')) return fallback;

  var lower = text.toLowerCase();
  if (lower.contains('insufficient_balance') ||
      lower.contains('insufficient balance')) {
    return 'Not enough balance. Top up or refer a friend to earn \$0.50!';
  }
  if (lower.contains('activation not found') ||
      lower.contains('not_found') ||
      lower.contains('user not found')) {
    return 'That number session is no longer active. Please buy a new number.';
  }
  if (lower.contains('did not have this in stock') ||
      lower.contains('out of stock') ||
      lower.contains('no numbers') ||
      lower.contains('no_numbers') ||
      lower.contains('not have this') ||
      lower.contains('no free phones')) {
    return 'FBGSMS does not have this number in stock right now. '
        'Please choose another country or service.';
  }

  // Strip any supplier branding that survived the checks above.
  for (final brand in _kUpstreamBrands) {
    text = text.replaceAll(
        RegExp(RegExp.escape(brand), caseSensitive: false), 'FBGSMS');
  }
  text = text.replaceAll(RegExp(r'\bhero\b', caseSensitive: false), 'FBGSMS');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  lower = text.toLowerCase();
  if (lower.contains('did not have this in stock') ||
      lower.contains('out of stock')) {
    return 'FBGSMS does not have this number in stock right now. '
        'Please choose another country or service.';
  }
  return text.isEmpty ? fallback : text;
}

/// Interpreted result of a single /api/check-sms poll.
class SmsPollResult {
  final String? code;
  final String? fatalMessage;
  const SmsPollResult({this.code, this.fatalMessage});
  bool get isWaiting => code == null && fatalMessage == null;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If any widget throws while building, show the error on screen instead of
  // a blank window, so we can always see what went wrong.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'UI ERROR:\n\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ),
    );
  };

  
  // Restore the login token before any screen can make a request. Without
  // this, a restored session would call the API anonymously.
  await ApiAuth.load();

  // A 401 means the token expired (7 days) or the account changed. Drop the
  // saved session and return to Login instead of leaving a half-dead screen.
  ApiAuth.onSessionExpired = () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      await prefs.remove('user_email');
    } catch (_) {}
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(
          notice: "Your session expired. Please log in again.",
        ),
      ),
      (route) => false,
    );
  };

  int? savedUserId;
  String? savedEmail;

  // Auto-login logic
  try {
    final prefs = await SharedPreferences.getInstance();
    savedUserId = prefs.getInt('user_id');
    savedEmail = prefs.getString('user_email');
  } catch (e) {
    print("Storage blocked on startup: $e");
  }

  // If we have a user id but no token, the session predates token auth.
  // Force a fresh login instead of making unauthenticated calls.
  if (savedUserId != null && !ApiAuth.isLoggedIn) {
    savedUserId = null;
    savedEmail = null;
  }

  runApp(MyApp(
    initialUserId: savedUserId,
    initialEmail: savedEmail,
  ));
}

class MyApp extends StatelessWidget {
  final int? initialUserId;
  final String? initialEmail;

  const MyApp({super.key, this.initialUserId, this.initialEmail});

  @override
  Widget build(BuildContext context) {
    const Color neonGreen = Color(0xFF00FF41);
    const Color darkBg = Color(0xFF0F0F0F);
    const Color darkCard = Color(0xFF1A1A1A);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'FBG SMS',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: neonGreen,
        scaffoldBackgroundColor: darkBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkCard,
          foregroundColor: neonGreen,
          elevation: 0,
        ),
        cardColor: darkCard,
        cardTheme: CardThemeData(
          color: darkCard,
          elevation: 8,
          shadowColor: neonGreen.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: neonGreen.withValues(alpha: 0.3), width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: neonGreen,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: neonGreen,
            side: const BorderSide(color: neonGreen),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: neonGreen.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: neonGreen.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: neonGreen, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIconColor: neonGreen,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkCard,
          selectedItemColor: neonGreen,
          unselectedItemColor: Colors.grey,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        colorScheme: const ColorScheme.dark(
          primary: neonGreen,
          secondary: neonGreen,
          surface: darkCard,
        ),
      ),
      home: initialUserId != null && initialEmail != null
          ? HomeScreen(userId: initialUserId!, email: initialEmail!)
          : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============== SERVICE ICON MAPPER ==============
// Every service in the catalogue gets a branded icon and colour. The lookup is
// driven by the service name returned by the API (the short service code is not
// reliable for this backend), with category fallbacks for regional brands.

class ServiceLook {
  final FaIconData icon;
  final Color color;
  const ServiceLook(this.icon, this.color);
}

class _BrandRule {
  final List<String> keys;
  final ServiceLook look;
  const _BrandRule(this.keys, this.look);
}

const List<_BrandRule> _brandRules = <_BrandRule>[
  _BrandRule(["whatsapp", "whats app", "whatsapp business"],
      ServiceLook(FontAwesomeIcons.whatsapp, Color(0xFF25D366))), // WhatsApp
  _BrandRule(["telegram"],
      ServiceLook(FontAwesomeIcons.telegram, Color(0xFF229ED9))), // Telegram
  _BrandRule(["facebook", "messenger"],
      ServiceLook(FontAwesomeIcons.facebookF, Color(0xFF1877F2))), // Facebook
  _BrandRule(["instagram", "insta", "threads"],
      ServiceLook(FontAwesomeIcons.instagram, Color(0xFFE1306C))), // Instagram
  _BrandRule(["tiktok", "douyin"],
      ServiceLook(FontAwesomeIcons.tiktok, Color(0xFFFF0050))), // TikTok
  _BrandRule(["twitter", "x com", "xtwitter"],
      ServiceLook(FontAwesomeIcons.xTwitter, Color(0xFF1DA1F2))), // X / Twitter
  _BrandRule(["discord"],
      ServiceLook(FontAwesomeIcons.discord, Color(0xFF5865F2))), // Discord
  _BrandRule(["snapchat"],
      ServiceLook(FontAwesomeIcons.snapchat, Color(0xFFFFFC00))), // Snapchat
  _BrandRule(["reddit"],
      ServiceLook(FontAwesomeIcons.redditAlien, Color(0xFFFF4500))), // Reddit
  _BrandRule(["pinterest"],
      ServiceLook(FontAwesomeIcons.pinterest, Color(0xFFE60023))), // Pinterest
  _BrandRule(["linkedin"],
      ServiceLook(FontAwesomeIcons.linkedinIn, Color(0xFF0A66C2))), // LinkedIn
  _BrandRule(["youtube"],
      ServiceLook(FontAwesomeIcons.youtube, Color(0xFFFF0000))), // YouTube
  _BrandRule(["twitch"],
      ServiceLook(FontAwesomeIcons.twitch, Color(0xFF9146FF))), // Twitch
  _BrandRule(["vk com", "=vk"],
      ServiceLook(FontAwesomeIcons.vk, Color(0xFF0077FF))), // VK
  _BrandRule(["ok ru", "odnoklassniki"],
      ServiceLook(FontAwesomeIcons.odnoklassniki, Color(0xFFEE8208))), // OK.ru
  _BrandRule(["wechat", "weixin"],
      ServiceLook(FontAwesomeIcons.weixin, Color(0xFF07C160))), // WeChat
  _BrandRule(["tencent qq", "=qq"],
      ServiceLook(FontAwesomeIcons.qq, Color(0xFF12B7F5))), // QQ
  _BrandRule(["weibo"],
      ServiceLook(FontAwesomeIcons.weibo, Color(0xFFE6162D))), // Weibo
  _BrandRule(["line messenger", "=line"],
      ServiceLook(FontAwesomeIcons.line, Color(0xFF06C755))), // LINE
  _BrandRule(["kakaotalk", "kakao"],
      ServiceLook(FontAwesomeIcons.kakaoTalk, Color(0xFFFEE500))), // KakaoTalk
  _BrandRule(["viber"],
      ServiceLook(FontAwesomeIcons.viber, Color(0xFF7360F2))), // Viber
  _BrandRule(["signal"],
      ServiceLook(FontAwesomeIcons.signal, Color(0xFF3A76F0))), // Signal
  _BrandRule(["skype"],
      ServiceLook(FontAwesomeIcons.skype, Color(0xFF00AFF0))), // Skype
  _BrandRule(["zoom", "voov meeting"],
      ServiceLook(FontAwesomeIcons.zoom, Color(0xFF2D8CFF))), // Zoom
  _BrandRule(["google chat", "google messenger", "groupme"],
      ServiceLook(FontAwesomeIcons.commentDots, Color(0xFF00AC47))), // Google chat
  _BrandRule(["gmail", "=go"],
      ServiceLook(FontAwesomeIcons.envelope, Color(0xFFEA4335))), // Gmail
  _BrandRule(["google voice", "textfree", "textnow"],
      ServiceLook(FontAwesomeIcons.commentSms, Color(0xFF4285F4))), // SMS app
  _BrandRule(["twilio", "vonage"],
      ServiceLook(FontAwesomeIcons.commentSms, Color(0xFFF22F46))), // SMS gateway
  _BrandRule(["google", "gmail"],
      ServiceLook(FontAwesomeIcons.google, Color(0xFF4285F4))), // Google
  _BrandRule(["imo", "botim", "yalla", "zalo", "mchat", "tangtan", "tantan", "beboo", "soulapp", "jacob", "weverse", "hily", "tango"],
      ServiceLook(FontAwesomeIcons.commentDots, Color(0xFF229ED9))), // Messenger
  _BrandRule(["clubhouse"],
      ServiceLook(FontAwesomeIcons.microphone, Color(0xFFF0E6D2))), // Clubhouse
  _BrandRule(["bigo live", "bigo", "kwai", "vidio"],
      ServiceLook(FontAwesomeIcons.video, Color(0xFFFF4B4B))), // Video app
  _BrandRule(["any other", "other"],
      ServiceLook(FontAwesomeIcons.questionCircle, Color(0xFF9E9E9E))), // Other
  _BrandRule(["full rent", "=full"],
      ServiceLook(FontAwesomeIcons.infinity, Color(0xFF00FF41))), // Full rent
  _BrandRule(["tinder", "bumble", "hinge", "okcupid", "ok cupid", "pof", "plenty of fish", "badoo", "mamba", "lovoo", "happn", "skout", "tagged", "meetme", "feeld", "dil mil", "jeevansathi", "shaadi", "cupid", "cupidmedia", "lovescout24", "parship", "muzz", "wooplus", "lovense", "chispa", "justdating", "just dating", "mocospace", "roomster", "=match", "love", "smitten", "milanuncios"],
      ServiceLook(FontAwesomeIcons.heart, Color(0xFFFF4E6A))), // Dating
  _BrandRule(["grindr"],
      ServiceLook(FontAwesomeIcons.heart, Color(0xFFF5A623))), // Grindr
  _BrandRule(["paypal"],
      ServiceLook(FontAwesomeIcons.paypal, Color(0xFF00457C))), // PayPal
  _BrandRule(["stripe"],
      ServiceLook(FontAwesomeIcons.stripe, Color(0xFF635BFF))), // Stripe
  _BrandRule(["apple pay"],
      ServiceLook(FontAwesomeIcons.applePay, Color(0xFF000000))), // Apple Pay
  _BrandRule(["google pay", "gpay"],
      ServiceLook(FontAwesomeIcons.googlePay, Color(0xFF4285F4))), // Google Pay
  _BrandRule(["amazon pay"],
      ServiceLook(FontAwesomeIcons.amazonPay, Color(0xFFFF9900))), // Amazon Pay
  _BrandRule(["alipay", "alibaba", "1688", "taobao", "tmall"],
      ServiceLook(FontAwesomeIcons.alipay, Color(0xFF1677FF))), // Alipay
  _BrandRule(["unionpay", "visa", "mastercard"],
      ServiceLook(FontAwesomeIcons.creditCard, Color(0xFF1A1F71))), // Card scheme
  _BrandRule(["wise", "revolut", "venmo", "cash app", "cashapp", "zelle", "monzo", "monese", "venmo", "square", "sumup", "chime", "varo", "sofi", "current", "chime"],
      ServiceLook(FontAwesomeIcons.moneyBillTransfer, Color(0xFF00B26B))), // Money app
  _BrandRule(["skrill", "neteller", "payoneer", "paysera", "paytm", "phonepe", "mobikwik", "freecharge", "true money", "truemoney", "gcash", "dana", "ovo", "gopay", "linkaja", "shopeepay", "doku", "akulaku", "kredivo", "jenius", "maya", "paycell", "papara", "payfix", "iyzico", "qiwi", "webmoney", "payeer", "advcash", "perfect money", "paysafecard", "ecopayz", "bharatpe", "bharat pe", "astrapay", "yoomoney", "yandex money", "moneylion", "remitly", "worldremit", "transfergo", "sendwave", "taptap send", "ria", "paysend", "xoom", "payoneer", "skrill", "neosurf", "paywell", "onepay", "minipay", "qpon", "shopback", "mycashbacks"],
      ServiceLook(FontAwesomeIcons.wallet, Color(0xFF00A3FF))), // Wallet
  _BrandRule(["klarna", "clearpay", "afterpay", "affirm", "scalapay", "zilch", "tabby", "tamara", "paypal", "klarna", "paylater"],
      ServiceLook(FontAwesomeIcons.creditCard, Color(0xFFFFB3C7))), // Buy now pay later
  _BrandRule(["nubank", "itau", "bradesco", "santander", "caixa", "banco", "bancolombia", "sicredi", "pagbank", "agibank", "capital one", "dbs bank", "ally", "monobank", "privat", "privat24", "tinkoff", "sberbank", "sber", "neftm", "bpi", "bdo", "bca", "mandiri", "bri", "bni", "dbs", "tbank", "tinkoff", "credinex", "unicredit", "raiffeisen"],
      ServiceLook(FontAwesomeIcons.buildingColumns, Color(0xFF1565C0))), // Bank
  _BrandRule(["binance", "okx", "bybit", "kucoin", "kcex", "mexc", "bitrue", "bitget", "cryptocom", "crypto com", "cryptonow", "bitcoinbon", "bitso", "bitpay", "coinbase", "kraken", "bitfinex", "huobi", "gate io", "poloniex"],
      ServiceLook(FontAwesomeIcons.bitcoin, Color(0xFFF7931A))), // Crypto exchange
  _BrandRule(["metamask", "ethereum", "=eth"],
      ServiceLook(FontAwesomeIcons.ethereum, Color(0xFF627EEA))), // Ethereum
  _BrandRule(["bitcoin", "=btc"],
      ServiceLook(FontAwesomeIcons.bitcoin, Color(0xFFF7931A))), // Bitcoin
  _BrandRule(["litecoin"],
      ServiceLook(FontAwesomeIcons.litecoinSign, Color(0xFF345D9D))), // Litecoin
  _BrandRule(["monero"],
      ServiceLook(FontAwesomeIcons.monero, Color(0xFFFF6600))), // Monero
  _BrandRule(["solana"],
      ServiceLook(FontAwesomeIcons.solana, Color(0xFF9945FF))), // Solana
  _BrandRule(["tether", "usdt", "tron", "trx"],
      ServiceLook(FontAwesomeIcons.coins, Color(0xFF26A17B))), // Stablecoin
  _BrandRule(["moonpay", "trust wallet", "exodus", "wallet"],
      ServiceLook(FontAwesomeIcons.wallet, Color(0xFFF5A623))), // Crypto wallet
  _BrandRule(["steam"],
      ServiceLook(FontAwesomeIcons.steam, Color(0xFF66C0F4))), // Steam
  _BrandRule(["battlenet", "blizzard"],
      ServiceLook(FontAwesomeIcons.battleNet, Color(0xFF148EFF))), // Battle.net
  _BrandRule(["xbox"],
      ServiceLook(FontAwesomeIcons.xbox, Color(0xFF107C10))), // Xbox
  _BrandRule(["playstation"],
      ServiceLook(FontAwesomeIcons.playstation, Color(0xFF003791))), // PlayStation
  _BrandRule(["epic games", "roblox", "ubisoft", "nexon", "netmarble", "supercell", "nintendo", "pubg", "genshin", "riot games", "ea games", "game", "games", "gaming", "playtime", "taptap", "zynga", "kabam", "razer", "perfect world", "snkrdunk"],
      ServiceLook(FontAwesomeIcons.gamepad, Color(0xFF7B1FA2))), // Gaming
  _BrandRule(["minecraft", "tarkov"],
      ServiceLook(FontAwesomeIcons.cube, Color(0xFF62B47A))), // Game
  _BrandRule(["amazon"],
      ServiceLook(FontAwesomeIcons.amazon, Color(0xFFFF9900))), // Amazon
  _BrandRule(["ebay"],
      ServiceLook(FontAwesomeIcons.ebay, Color(0xFFE53238))), // eBay
  _BrandRule(["etsy"],
      ServiceLook(FontAwesomeIcons.etsy, Color(0xFFF16521))), // Etsy
  _BrandRule(["shopify"],
      ServiceLook(FontAwesomeIcons.shopify, Color(0xFF95BF47))), // Shopify
  _BrandRule(["aliexpress", "alibaba"],
      ServiceLook(FontAwesomeIcons.cartShopping, Color(0xFFFF4747))), // AliExpress
  _BrandRule(["shopee"],
      ServiceLook(FontAwesomeIcons.bagShopping, Color(0xFFEE4D2D))), // Shopee
  _BrandRule(["lazada", "tokopedia", "bukalapak", "blibli", "jd com", "jdcom", "pinduoduo", "temu", "shein", "wish", "rakuten", "mercado livre", "mercadolivre", "magalu", "americanas", "hepsiburada", "trendyol", "n11", "emag", "allegro", "ozon", "wildberries", "shafa", "sephora", "shop", "store", "mart", "market", "marketplace"],
      ServiceLook(FontAwesomeIcons.bagShopping, Color(0xFFFF6B00))), // Marketplace
  _BrandRule(["flipkart", "myntra", "meesho", "snapdeal", "tatacliq", "jiomart", "bigbasket", "zepto", "blinkit", "instamart", "zepto"],
      ServiceLook(FontAwesomeIcons.cartShopping, Color(0xFF2874F0))), // Indian retail
  _BrandRule(["swiggy", "zomato", "dunzo", "wolt", "deliveroo", "glovo", "foodora", "foodpanda", "just eat", "doordash", "grubhub", "postmates", "ifood", "rappi", "talabat", "hungerstation", "ubereats", "delivery", "dostavista", "foody", "efood", "=te", "bolt food", "samokat", "yemeksepeti", "getir", "gopuff", "food"],
      ServiceLook(FontAwesomeIcons.motorcycle, Color(0xFFFF5A00))), // Delivery
  _BrandRule(["uber"],
      ServiceLook(FontAwesomeIcons.uber, Color(0xFF276EF1))), // Uber
  _BrandRule(["lyft"],
      ServiceLook(FontAwesomeIcons.lyft, Color(0xFFFF00BF))), // Lyft
  _BrandRule(["bolt"],
      ServiceLook(FontAwesomeIcons.bolt, Color(0xFF34D186))), // Bolt
  _BrandRule(["grab"],
      ServiceLook(FontAwesomeIcons.car, Color(0xFF00B14F))), // Grab
  _BrandRule(["gojek", "indriver", "maxim", "didi", "cabify", "free now", "freenow", "gett", "blablacar", "bla bla car", "ryde", "careem", "heetch", "uklon", "99app", "ola", "olacabs", "taxi", "ride", "rides", "yandex go", "shuttle", "dott", "voi", "tier", "lime"],
      ServiceLook(FontAwesomeIcons.car, Color(0xFFFFC400))), // Ride hailing
  _BrandRule(["walmart", "target", "costco", "best buy", "ikea", "lidl", "aldi", "carrefour", "auchan", "magnit", "pyaterochka", "perekrestok", "dixie", "lenta", "=metro", "7 eleven", "seven eleven", "alfamidi", "alfamart", "indomaret", "lotteria", "dairy farm", "cvs", "walgreens", "boots", "dm", "rossmann", "notino", "watsons", "guardian", "miniso", "daiso", "action", "normal", "circle k", "familymart", "lawson", "ok mart"],
      ServiceLook(FontAwesomeIcons.store, Color(0xFF4CAF50))), // Store
  _BrandRule(["vinted", "depop", "poshmark", "dolap", "zara", "h m", "uniqlo", "gap", "shein", "asos", "boohoo", "zalando", "footdistrict", "foot locker", "nike", "adidas", "puma", "reebok", "under armour", "decathlon"],
      ServiceLook(FontAwesomeIcons.shirt, Color(0xFF00BCD4))), // Fashion
  _BrandRule(["leboncoin", "marktplaats", "marktde", "kleinanzeigen", "olx", "gumtree", "craigslist", "wallapop", "mercari", "shpock", "offerup", "letgo", "subito", "2dehands", "2ememain", "quoka", "sahibinden", "avito", "youla", "annoncelight", "bazaraki", "jofogas", "hj", "dba", "willhaben"],
      ServiceLook(FontAwesomeIcons.tag, Color(0xFFFF6E14))), // Classifieds
  _BrandRule(["nike", "adidas", "puma", "reebok", "shoe", "sneaker"],
      ServiceLook(FontAwesomeIcons.shoePrints, Color(0xFF111111))), // Footwear
  _BrandRule(["starbucks", "costa", "caffe nero", "dunkin", "tim hortons", "coffee", "espresso", "cafe", "nero", "chagee", "tealive", "zus coffee", "kopi", "tomoro", "luckin"],
      ServiceLook(FontAwesomeIcons.mugHot, Color(0xFF00704A))), // Coffee
  _BrandRule(["mcdonald", "burger king", "wendys", "five guys", "shake shack", "guzman", "burger"],
      ServiceLook(FontAwesomeIcons.burger, Color(0xFFFFC72C))), // Burgers
  _BrandRule(["kfc", "popeyes", "drumstick", "nandos"],
      ServiceLook(FontAwesomeIcons.drumstickBite, Color(0xFFE4002B))), // Fried chicken
  _BrandRule(["domino", "pizza hut", "pizza", "papa john"],
      ServiceLook(FontAwesomeIcons.pizzaSlice, Color(0xFFFF0000))), // Pizza
  _BrandRule(["subway", "sandwich", "greggs", "pret", "bakery", "bread"],
      ServiceLook(FontAwesomeIcons.breadSlice, Color(0xFF008C15))), // Sandwich
  _BrandRule(["7 eleven", "seven eleven", "shell", "bp", "chevron", "enilive", "lukoil", "rosneft", "gas", "fuel", "petrol", "caltex", "shellbox", "total energies", "circle k", "q8", "esso", "petronas"],
      ServiceLook(FontAwesomeIcons.gasPump, Color(0xFFFBCE07))), // Fuel
  _BrandRule(["coca cola", "cocacola", "pepsi", "red bull", "monster", "drink", "beverage", "corona", "heineken", "budweiser", "beer", "brahma", "tennents", "sy", "prom"],
      ServiceLook(FontAwesomeIcons.bottleWater, Color(0xFFE53935))), // Drinks
  _BrandRule(["cadbury", "nestle", "ferrero", "nutella", "hersh", "oreo", "kitkat", "chocolate", "candy", "snack"],
      ServiceLook(FontAwesomeIcons.cookie, Color(0xFF6D4C41))), // Snacks
  _BrandRule(["netflix", "disney", "hulu", "prime video", "hbo", "paramount", "crunchyroll", "ivi", "okko", "wink", "zee5", "zeenow", "sonyliv", "hotstar", "mytvsuper", "skytv", "viaplay", "canal", "molotov", "streaming", "movie", "movies", "film", "cinema", "viu", "wetv", "iqiyi", "youku", "bilibili"],
      ServiceLook(FontAwesomeIcons.play, Color(0xFFE50914))), // Streaming
  _BrandRule(["spotify"],
      ServiceLook(FontAwesomeIcons.spotify, Color(0xFF1DB954))), // Spotify
  _BrandRule(["soundcloud", "deezer", "tidal", "shazam", "audiomack", "joox", "gaana", "wynk", "napster", "pandora", "anghami", "music"],
      ServiceLook(FontAwesomeIcons.music, Color(0xFFFF5500))), // Music
  _BrandRule(["rutube", "vimeo", "dailymotion", "kick", "twitch", "video"],
      ServiceLook(FontAwesomeIcons.video, Color(0xFF1AB7EA))), // Video
  _BrandRule(["airbnb"],
      ServiceLook(FontAwesomeIcons.airbnb, Color(0xFFFF5A5F))), // Airbnb
  _BrandRule(["booking", "hotels com", "agoda", "trivago", "expedia", "hostel", "hotel", "stay", "traveloka", "tikett", "oyo"],
      ServiceLook(FontAwesomeIcons.bed, Color(0xFF003580))), // Hotels
  _BrandRule(["trip", "skyscanner", "kiwi", "ryanair", "easyjet", "emirates", "qatar", "turkish airlines", "pegasus", "airlines", "airways", "flight", "fly", "airasia", "lufthansa", "klm", "air france", "iberia", "vueling", "wizz", "jet2", "southwest", "delta", "united", "american airlines", "make my trip", "makemytrip", "yatra", "cleartrip", "tongcheng"],
      ServiceLook(FontAwesomeIcons.plane, Color(0xFF0288D1))), // Travel
  _BrandRule(["irctc", "trainline", "sncf", "deutsche bahn", "renfe", "trenitalia", "amtrak", "railway", "rail", "train", "jt express", "whoosh", "swarail"],
      ServiceLook(FontAwesomeIcons.train, Color(0xFF0F3C8B))), // Rail
  _BrandRule(["flixbus", "redbus", "bus", "greyhound", "megabus"],
      ServiceLook(FontAwesomeIcons.bus, Color(0xFFD32F2F))), // Bus
  _BrandRule(["2gis", "amap", "google maps", "maps", "gps", "navigator"],
      ServiceLook(FontAwesomeIcons.map, Color(0xFF34A853))), // Maps
  _BrandRule(["airtel", "jio", "vodafone", "t mobile", "t online", "o2", "orange", "sfr", "bouygues", "=free", "drei", "lycamobile", "lebara", "giffgaff", "=ee", "=three", "mts", "megafon", "beeline", "tele2", "kyivstar", "lifecell", "turkcell", "avea", "zong", "jazz", "ufone", "telenor", "claro", "=vivo", "tim", "=oi", "entel", "movistar", "telcel", "at t", "verizon", "telecom", "mobile", "cellular", "sim", "network", "telefonica", "optus", "telstra", "singtel", "starhub", "globe", "smart"],
      ServiceLook(FontAwesomeIcons.simCard, Color(0xFF7E57C2))), // Mobile operator
  _BrandRule(["samsung", "xiaomi", "huawei", "oppo", "realme", "oneplus", "motorola", "nokia", "sony", "lg", "device", "phone", "handset"],
      ServiceLook(FontAwesomeIcons.mobileScreen, Color(0xFF1565C0))), // Device
  _BrandRule(["openai", "chatgpt", "claude", "gemini", "grok", "perplexity", "kimi", "grok", "manus", "genspark", "alchemia", "lightning ai", "siliconflow", "volcengine", "sagemaker", "kaggle", "hugging"],
      ServiceLook(FontAwesomeIcons.robot, Color(0xFF10A37F))), // AI service
  _BrandRule(["github"],
      ServiceLook(FontAwesomeIcons.github, Color(0xFF181717))), // GitHub
  _BrandRule(["gitlab", "bitbucket", "linode", "hostinger", "vercel", "strato", "beget", "cloud", "hosting", "server", "vps", "aws", "azure", "digitalocean", "cloudflare", "firebase", "cloud ru", "uol host", "hostgator", "godaddy", "namecheap"],
      ServiceLook(FontAwesomeIcons.server, Color(0xFFFF9900))), // Hosting
  _BrandRule(["slack"],
      ServiceLook(FontAwesomeIcons.slack, Color(0xFF4A154B))), // Slack
  _BrandRule(["salesforce"],
      ServiceLook(FontAwesomeIcons.salesforce, Color(0xFF00A1E0))), // Salesforce
  _BrandRule(["yahoo", "=mb", "aol", "gmx", "web de", "mail ru", "rediffmail", "protonmail", "zoho", "mail", "email", "tuta", "yandex mail"],
      ServiceLook(FontAwesomeIcons.envelope, Color(0xFF6001D2))), // Mail
  _BrandRule(["steam", "epic", "ubisoft"],
      ServiceLook(FontAwesomeIcons.gamepad, Color(0xFF171A21))), // Games
  _BrandRule(["bet365", "betfair", "poker", "casino", "slots", "bet", "betting", "sportsbook", "bookmaker", "lottery", "lotto", "bingo", "sport", "sports", "gambling", "oddspedia", "1xbet", "betway", "william hill", "draftkings", "fanduel", "betano", "superbet", "unibet", "paddy power", "sky bet", "betclic", "winamax", "zonabets", "stoiximan", "betflag", "betlive", "betmen", "crystalbet", "eurobet", "admiralbet", "lottomatica", "casino plus", "las vegas", "big cash", "luckyland", "hitnspin", "high 5", "mrq", "mr q", "kwiff", "midnite", "bwin", "betsson"],
      ServiceLook(FontAwesomeIcons.dice, Color(0xFF43A047))), // Betting
  _BrandRule(["survey", "surveys", "opinion", "poll", "reward", "rewards", "rewardy", "cashback", "cash back", "points", "prodege", "yougov", "ipsos", "attapoll", "prime opinion", "five surveys", "askable", "prolific", "swagbucks", "inboxdollars", "toluna", "surveyon", "datanyze", "fieldstar", "alig", "radiate"],
      ServiceLook(FontAwesomeIcons.clipboardList, Color(0xFFFF9800))), // Surveys
  _BrandRule(["pharmacy", "apteka", "drug", "health", "clinic", "hospital", "doctor", "pill", "medic", "sanofi", "acuvue", "nutriclub", "gymplius", "fitness", "gym", "sportmaster", "ddx fitness", "classpass", "totalpass", "strava", "nike training"],
      ServiceLook(FontAwesomeIcons.capsules, Color(0xFFE91E63))), // Health
  _BrandRule(["uber", "taxi"],
      ServiceLook(FontAwesomeIcons.car, Color(0xFF000000))), // Taxi
  _BrandRule(["freelance", "upwork", "fiverr", "freelancer", "task", "airtasker", "thumbtack", "taskrabbit", "gigs", "workana", "peopleperhour"],
      ServiceLook(FontAwesomeIcons.briefcase, Color(0xFF14A800))), // Freelance
  _BrandRule(["job", "jobs", "career", "hire", "indeed", "linkedin", "hh", "glassdoor", "monster", "ziprecruiter", "jobstreet", "naukri", "infojobs", "pracuj"],
      ServiceLook(FontAwesomeIcons.briefcase, Color(0xFF0A66C2))), // Jobs
  _BrandRule(["learn", "course", "school", "academy", "edu", "study", "tutor", "onion academy", "skillshare", "udemy", "coursera", "duolingo", "khan", "quizlet", "brainly", "chegg", "gauth"],
      ServiceLook(FontAwesomeIcons.graduationCap, Color(0xFF3F51B5))), // Education
  _BrandRule(["game", "casino"],
      ServiceLook(FontAwesomeIcons.gamepad, Color(0xFF6A1B9A))), // Games
  _BrandRule(["apple"],
      ServiceLook(FontAwesomeIcons.apple, Color(0xFF000000))), // Apple
  _BrandRule(["microsoft"],
      ServiceLook(FontAwesomeIcons.microsoft, Color(0xFF00A4EF))), // Microsoft
  _BrandRule(["=meta"],
      ServiceLook(FontAwesomeIcons.meta, Color(0xFF0866FF))), // Meta
  _BrandRule(["yandex"],
      ServiceLook(FontAwesomeIcons.yandex, Color(0xFFFC3F1D))), // Yandex
  _BrandRule(["naver", "baidu", "quark", "zhihu", "rediffmail"],
      ServiceLook(FontAwesomeIcons.magnifyingGlass, Color(0xFF03C75A))), // Search portal
  _BrandRule(["redbook", "xiaohongshu"],
      ServiceLook(FontAwesomeIcons.book, Color(0xFFFF2442))), // RedBook
  _BrandRule(["adobe"],
      ServiceLook(FontAwesomeIcons.penNib, Color(0xFFFF0000))), // Adobe
  _BrandRule(["autodesk", "canva", "figma", "sketch"],
      ServiceLook(FontAwesomeIcons.penRuler, Color(0xFF0696D7))), // Design tool
  _BrandRule(["docusign", "hellosign", "signnow"],
      ServiceLook(FontAwesomeIcons.fileSignature, Color(0xFFFFCC22))), // e-Signature
  _BrandRule(["gofundme", "kickstarter", "patreon", "indiegogo"],
      ServiceLook(FontAwesomeIcons.handHoldingDollar, Color(0xFF00B964))), // Funding
  _BrandRule(["nextdoor"],
      ServiceLook(FontAwesomeIcons.house, Color(0xFF8ED500))), // Nextdoor
  _BrandRule(["carousell", "redbubble", "grailed", "voggt", "meiqfashion", "gardrops", "oskelly", "vinted"],
      ServiceLook(FontAwesomeIcons.tag, Color(0xFFFF5722))), // Resale
  _BrandRule(["truecaller", "caller", "callapp"],
      ServiceLook(FontAwesomeIcons.phone, Color(0xFF0086FF))), // Caller ID
  _BrandRule(["opera", "firefox", "chrome", "brave", "browser"],
      ServiceLook(FontAwesomeIcons.firefoxBrowser, Color(0xFFFF1B2D))), // Browser
  _BrandRule(["etoro", "tradingview", "binance", "invest", "broker", "trade republic", "scalable", "t212", "xtb", "plus500", "ig group", "cmc markets"],
      ServiceLook(FontAwesomeIcons.chartLine, Color(0xFF00C805))), // Trading
  _BrandRule(["mypos", "sumup", "square", "izettle", "clover", "paywell", "getnet", "cielo", "stone", "asaas", "pagaleve", "recargapay", "picpay", "infinite pay", "kredito", "kredivo", "credinex", "ada modal", "bunq", "bipa", "pockit", "finplus", "easycash", "monese", "curve", "zinia", "astropay", "flink", "flink", "tala", "kaito"],
      ServiceLook(FontAwesomeIcons.creditCard, Color(0xFF00B26B))), // Fintech
  _BrandRule(["seloger", "immoscout", "idealista", "immowelt", "99acres", "immo", "real estate", "housing", "property", "zillow", "rightmove", "fotocasa", "habitaclia", "casa it", "domclick", "cian", "njuškalo", "njuskalo", "skelbiu", "leolist", "marktplaats"],
      ServiceLook(FontAwesomeIcons.house, Color(0xFFFF7043))), // Real estate
  _BrandRule(["novaposhta", "inpost", "cdek", "meest", "dhl", "fedex", "ups", "post", "shipping", "courier", "delivery", "jt express", "jt", "kerry", "flash", "spx", "ninja van", "giao"],
      ServiceLook(FontAwesomeIcons.truck, Color(0xFFFFB300))), // Shipping
  _BrandRule(["air miles", "smiles", "bonuslink", "loyalty", "rewards", "rewardy", "myvalue", "gpnbonus", "pockit", "shopback", "mycashbacks", "fetch", "receipt"],
      ServiceLook(FontAwesomeIcons.star, Color(0xFFFFD700))), // Loyalty
  _BrandRule(["paddy power", "skybet", "sky bet", "wepoker", "conticazino", "my11circle", "dream11", "rummycircle", "zupee", "winzogame", "opap", "fdj", "parionssport", "crocobet", "betano", "superbet", "stoiximan", "betflag", "betlive", "betmen", "crystalbet", "eurobet", "admiralbet", "lottomatica", "casino plus", "las vegas", "big cash", "luckyland", "hitnspin", "high 5", "mrq", "kwiff", "midnite", "bet365", "betfair", "poker", "casino", "slot", "bingo", "lottery", "lotto", "sportsbook", "bookmaker", "betting", "wager", "gambling", "oddspedia", "1xbet", "betway", "william hill", "draftkings", "fanduel", "unibet", "betclic", "winamax", "stoiximan", "bwin", "betsson", "pariurilor", "winner", "netwin", "twin", "rush", "gg", "d4", "playojo", "ladbrokes", "coral", "pokerstars"],
      ServiceLook(FontAwesomeIcons.dice, Color(0xFF43A047))), // Betting
  _BrandRule(["dodopizza", "domino", "pizza", "papa john"],
      ServiceLook(FontAwesomeIcons.pizzaSlice, Color(0xFFFF0000))), // Pizza
  _BrandRule(["vkusno i tochka", "burger", "mcdonald", "kfc", "subway", "greggs", "bakery"],
      ServiceLook(FontAwesomeIcons.burger, Color(0xFFFFC72C))), // Fast food
  _BrandRule(["eleme", "aiqfome", "keeta", "meituan", "foody", "efood", "hungerstation", "talabat", "deliveroo", "glovo", "wolt", "rappi", "ifood", "just eat", "doordash", "gopuff", "lalamove", "bring", "foodora", "foodpanda", "swiggy", "zomato", "zepto", "blinkit", "instamart", "getir", "grab food"],
      ServiceLook(FontAwesomeIcons.motorcycle, Color(0xFFFF5A00))), // Delivery
  _BrandRule(["biedronka", "zabka", "vkusvill", "magnolia", "monetka", "lemana", "obi", "dixie", "aukro", "silpo", "citymall", "jb hi fi", "alfagift", "indopaket", "indosaku", "chocofamily", "flowwow", "shokoladnica", "billa", "kaufland", "tesco", "sainsbury", "asda", "morrisons", "waitrose", "coop", "spar", "migros", "rewe", "edeka", "netto", "penny", "bim", "a101", "sok", "carrefour", "auchan", "=metro", "selgros", "profi", "mega image", "shop", "store", "market", "mart", "supermarket", "grocery", "retail", "outlet", "mall"],
      ServiceLook(FontAwesomeIcons.store, Color(0xFF4CAF50))), // Store
  _BrandRule(["allobank", "jago", "seabank", "blu", "bca", "bri", "bni", "mandiri", "cimb", "permata", "danamon", "panin", "mega", "btpn", "nubank", "itau", "bradesco", "santander", "caixa", "inter", "sicredi", "pagbank", "agibank", "banco", "bank", "dbs", "ocbc", "uob", "maybank", "rhb", "hong leong", "ambank", "public bank", "scb", "kasikorn", "krungthai", "bangkok bank", "tmb", "ayudhya", "bpi", "bdo", "metrobank", "landbank", "unionbank", "rcbc", "security bank", "chinabank", "sky", "bancolombia", "davivienda", "bbva", "santander", "hsbc", "barclays", "lloyds", "natwest", "monzo", "starling", "revolut", "n26", "comdirect", "ing", "abn amro", "rabobank", "ing bank", "millennium", "pko", "mbank", "pekao", "alior", "santander bank", "monobank", "privat24", "oschadbank", "ukrsibbank", "raiffeisen", "otp", "kbc", "belfius", "postbank", "sparkasse", "volksbank", "unicredit", "intesa", "bnl", "mps", "credem", "bper", "desio", "bancoposta", "bbva", "caixabank", "sabadell", "bankinter", "abanca", "unicaja", "kutxabank", "ibercaja", "popular", "caja rural"],
      ServiceLook(FontAwesomeIcons.buildingColumns, Color(0xFF1565C0))), // Bank
  _BrandRule(["immoscout", "otzovik", "otzyv", "review", "trustpilot", "yelp", "tripadvisor", "sikayet", "sravni", "compare", "check24", "idealo", "price", "shopping comparison"],
      ServiceLook(FontAwesomeIcons.starHalfStroke, Color(0xFF00AA6C))), // Reviews
  _BrandRule(["natura", "avon", "oriflame", "mary kay", "cosmetic", "beauty", "makeup", "sephora", "watsons", "guardian", "panvel", "letual", "riv gosh", "beauty"],
      ServiceLook(FontAwesomeIcons.sprayCan, Color(0xFFE91E63))), // Beauty
  _BrandRule(["govbr", "gov", "government", "public", "tax", "pension", "bpjstk", "social security", "federal", "municipal", "prefeitura", "detran", "inss", "receita"],
      ServiceLook(FontAwesomeIcons.landmarkFlag, Color(0xFF1E88E5))), // Government
  _BrandRule(["crypto", "coin", "token", "nft", "web3"],
      ServiceLook(FontAwesomeIcons.coins, Color(0xFFF7931A))), // Crypto
  _BrandRule(["ticketmaster", "kktix", "damai", "guiche", "ticket", "entradas", "tickets"],
      ServiceLook(FontAwesomeIcons.ticket, Color(0xFF026CDF))), // Ticketing
  _BrandRule(["mercado", "noon", "tata neu", "rozetka", "lamoda", "yappy", "hopi", "999 md", "mera gaon", "quero quero", "lotus", "continente", "mercadito", "falabella", "ripley", "elektra", "coppel", "liverpool", "suburbia", "chedraui", "soriana", "oxxo", "wong"],
      ServiceLook(FontAwesomeIcons.bagShopping, Color(0xFFFF6B00))), // Retail
  _BrandRule(["joyride", "move it", "binbin", "beebs", "motorku", "webmotors", "kolesa", "drom", "poparide", "myboost", "psa", "moto", "scooter", "autoshop", "karos", "drive2", "drive"],
      ServiceLook(FontAwesomeIcons.car, Color(0xFFFFC400))), // Vehicles
  _BrandRule(["max", "hot51", "all access", "smotryoshka", "duet", "mvideo", "kinopoisk", "premier", "start", "wink"],
      ServiceLook(FontAwesomeIcons.play, Color(0xFFE50914))), // Streaming
  _BrandRule(["paddy power", "paddypower", "sisal", "okbet", "arenaplus", "stanleybet", "stoloto", "bets", "jackpot", "spin", "bti", "bat"],
      ServiceLook(FontAwesomeIcons.dice, Color(0xFF43A047))), // Betting
  _BrandRule(["=her", "feels", "finya", "fotka", "feetfinder", "parenteam", "bunda", "veeka", "unni", "fruitz", "salams", "daki", "meeef", "erome", "ero me", "erome", "her", "erotic", "adult", "hookup", "sex", "escort", "onlyfans", "fansly", "stripchat", "chaturbate"],
      ServiceLook(FontAwesomeIcons.heart, Color(0xFFFF4E6A))), // Dating
  _BrandRule(["webde", "ukrnet", "sapo", "brevo", "newsletter", "zoho", "news"],
      ServiceLook(FontAwesomeIcons.envelope, Color(0xFF607D8B))), // Mail
  _BrandRule(["vfs", "passport", "visa application", "immigration", "embassy"],
      ServiceLook(FontAwesomeIcons.passport, Color(0xFF1E88E5))), // Immigration
  _BrandRule(["whatnot", "adverts", "tise", "bazos", "lalafo", "jofogas", "annonce", "annoncelight", "dabble", "marketed", "classified"],
      ServiceLook(FontAwesomeIcons.tag, Color(0xFFFF6E14))), // Classifieds
  _BrandRule(["eneba", "codashop", "offgamers", "nttgame", "netease", "boyaa", "gnjoy", "ankama", "zul", "geekay", "loloo", "intel sap", "ncsoft", "thefate", "this fate", "gameloop", "mobapk"],
      ServiceLook(FontAwesomeIcons.gamepad, Color(0xFF7B1FA2))), // Games
  _BrandRule(["langit musik", "joox", "anghami", "audible", "podcast", "audiobook"],
      ServiceLook(FontAwesomeIcons.music, Color(0xFFFF5500))), // Audio
  _BrandRule(["onet", "rumbler", "jush", "newspaper", "news app", "gazeta", "journal", "press"],
      ServiceLook(FontAwesomeIcons.newspaper, Color(0xFF455A64))), // News
  _BrandRule(["rebtel", "keepcalling", "sideline", "ring4", "nao me perturbe", "nao perturbe", "glo", "myglo", "lebara", "voip", "second line", "esim", "airalo", "nomad"],
      ServiceLook(FontAwesomeIcons.phone, Color(0xFF0086FF))), // Calling
  _BrandRule(["profee", "lemfi", "ozan", "infinite pay", "revolut", "fairfx", "caxton", "currensea"],
      ServiceLook(FontAwesomeIcons.moneyBillTransfer, Color(0xFF00B26B))), // Money transfer
  _BrandRule(["cmb", "mybca", "neon", "next", "upward", "genome", "chime", "monzo", "starling", "n26", "bunq", "tandem", "atom", "zopa"],
      ServiceLook(FontAwesomeIcons.buildingColumns, Color(0xFF1565C0))), // Bank
  _BrandRule(["fastwork", "thel", "oneforma", "outlier", "kabanchik", "teamoru", "switchup", "factory", "freelance", "gig", "task", "sidel", "upwork", "fiverr", "freelancer", "workana", "peopleperhour", "airtasker", "thumbtack"],
      ServiceLook(FontAwesomeIcons.briefcase, Color(0xFF14A800))), // Freelance
  _BrandRule(["seated", "thefork", "grupo madero", "restaurant", "dining", "resy", "opentable", "food"],
      ServiceLook(FontAwesomeIcons.utensils, Color(0xFFFF7043))), // Dining
  _BrandRule(["yara", "farmcare", "farm", "agro", "seed", "agriculture", "tani"],
      ServiceLook(FontAwesomeIcons.seedling, Color(0xFF4CAF50))), // Agri
  _BrandRule(["ultragaz", "gas", "fuel", "petrol", "energy", "electric", "lukoil", "shell", "bp", "=esso", "total"],
      ServiceLook(FontAwesomeIcons.gasPump, Color(0xFFFBCE07))), // Energy
  _BrandRule(["iqos", "vape", "tobacco", "smoking", "hookah"],
      ServiceLook(FontAwesomeIcons.smoking, Color(0xFF795548))), // Tobacco
  _BrandRule(["triumph", "enjoei", "privalia", "fashion", "clothing", "apparel", "garment", "boutique"],
      ServiceLook(FontAwesomeIcons.shirt, Color(0xFF00BCD4))), // Fashion
  _BrandRule(["cosmote", "myim3", "im3", "svyaz", "связь", "telco", "operator", "prepaid", "topup", "top up"],
      ServiceLook(FontAwesomeIcons.simCard, Color(0xFF7E57C2))), // Operator
  _BrandRule(["alchemy", "serpapi", "intel sap", "sap", "api", "developer", "infra"],
      ServiceLook(FontAwesomeIcons.server, Color(0xFFFF9900))), // Developer
  _BrandRule(["reclameaqui", "sikayet", "review", "reviews", "rating", "trustpilot", "complaint"],
      ServiceLook(FontAwesomeIcons.star, Color(0xFF00AA6C))), // Reviews
  _BrandRule(["cita previa", "cita", "appointment", "booking slot", "reserva", "schedule"],
      ServiceLook(FontAwesomeIcons.calendarCheck, Color(0xFF3F51B5))), // Appointments
  _BrandRule(["pets4homes", "pet", "pets", "vet", "animal"],
      ServiceLook(FontAwesomeIcons.paw, Color(0xFF8D6E63))), // Pets
  _BrandRule(["premmia", "gift", "voucher", "giftcard", "reward"],
      ServiceLook(FontAwesomeIcons.gift, Color(0xFFE91E63))), // Gifts
  _BrandRule(["warpcast", "mosgram", "ahlan", "wetalk", "bip", "tenchat", "momo", "soul", "chat", "dating"],
      ServiceLook(FontAwesomeIcons.commentDots, Color(0xFF229ED9))), // Chat
  _BrandRule(["switchup", "job", "career", "hire", "hiring", "employment"],
      ServiceLook(FontAwesomeIcons.briefcase, Color(0xFF0A66C2))), // Jobs
  _BrandRule(["atlas earth", "atlas", "maps", "geo", "location", "local"],
      ServiceLook(FontAwesomeIcons.map, Color(0xFF34A853))), // Maps
  _BrandRule(["дикси", "магнолия", "монетка", "лемана", "сільпо", "аптека", "пятёрочка", "перекрёсток", "лента", "ашан", "метро", "вкусвилл", "самокат", "магнит", "оби", "эльдорадо", "детский", "всеинструменты", "золотое", "блинбери", "лейка", "кари", "винлаб", "папer", "paper"],
      ServiceLook(FontAwesomeIcons.cartShopping, Color(0xFF4CAF50))), // Store (RU)
  _BrandRule(["столото", "лотерея", "лото"],
      ServiceLook(FontAwesomeIcons.dice, Color(0xFF43A047))), // Lottery
  _BrandRule(["почта", "связь", "элплат", "сотовый", "теле2", "билайн", "мегафон", "мтс"],
      ServiceLook(FontAwesomeIcons.simCard, Color(0xFF7E57C2))), // Operator (RU)
  _BrandRule(["домклик", "недвижимость", "квартира", "immobili", "immo"],
      ServiceLook(FontAwesomeIcons.house, Color(0xFFFF7043))), // Real estate
  _BrandRule(["газпром", "энерго", "энергия", "нефть"],
      ServiceLook(FontAwesomeIcons.gasPump, Color(0xFFFBCE07))), // Energy (RU)
  _BrandRule(["везёт", "везет", "такси", "авто", "автору", "моторан", "астра авто"],
      ServiceLook(FontAwesomeIcons.car, Color(0xFFFFC400))), // Vehicles (RU)
  _BrandRule(["вплюсе", "вчасно", "куулклевер", "голосза", "санофи", "напоправку", "робота", "работа"],
      ServiceLook(FontAwesomeIcons.briefcase, Color(0xFF0A66C2))), // Services (RU)
  _BrandRule(["сеть", "сервис", "центр", "клуб", "групп"],
      ServiceLook(FontAwesomeIcons.gear, Color(0xFF78909C))), // Service
];

// Fallbacks used when no specific brand matched the service name.
const List<_BrandRule> _categoryRules = <_BrandRule>[
  _BrandRule(["bet", "casino", "slot", "bingo", "poker", "lottery", "lotto", "wager", "sport"], ServiceLook(FontAwesomeIcons.dice, Color(0xFF43A047))),
  _BrandRule(["bank", "credit", "loan", "finance", "cash", "pay", "wallet", "money", "card", "fintech", "invest", "trade", "broker", "crypto", "coin"], ServiceLook(FontAwesomeIcons.wallet, Color(0xFF00A3FF))),
  _BrandRule(["shop", "store", "mart", "market", "buy", "deal", "sale", "retail", "mall", "cart"], ServiceLook(FontAwesomeIcons.cartShopping, Color(0xFFFF6B00))),
  _BrandRule(["food", "eat", "delivery", "restaurant", "pizza", "burger", "coffee", "cafe", "kitchen", "grocery"], ServiceLook(FontAwesomeIcons.motorcycle, Color(0xFFFF7043))),
  _BrandRule(["travel", "hotel", "flight", "air", "book", "tour", "trip", "bus", "train", "taxi", "ride", "car"], ServiceLook(FontAwesomeIcons.plane, Color(0xFF039BE5))),
  _BrandRule(["chat", "message", "messenger", "social", "talk", "app", "community", "forum", "date", "dating", "love", "match", "meet", "friend"], ServiceLook(FontAwesomeIcons.commentDots, Color(0xFF229ED9))),
  _BrandRule(["game", "play", "gaming", "esport"], ServiceLook(FontAwesomeIcons.gamepad, Color(0xFF7B1FA2))),
  _BrandRule(["tv", "video", "stream", "movie", "music", "radio", "podcast", "film"], ServiceLook(FontAwesomeIcons.play, Color(0xFFE50914))),
  _BrandRule(["health", "med", "care", "pharm", "clinic", "doctor", "dental", "pill"], ServiceLook(FontAwesomeIcons.heartPulse, Color(0xFFE91E63))),
  _BrandRule(["school", "learn", "study", "edu", "course", "academy", "university", "tutor"], ServiceLook(FontAwesomeIcons.graduationCap, Color(0xFF3F51B5))),
  _BrandRule(["mail", "email", "post"], ServiceLook(FontAwesomeIcons.envelope, Color(0xFF607D8B))),
  _BrandRule(["cloud", "host", "server", "vpn", "tech", "software", "dev", "code"], ServiceLook(FontAwesomeIcons.server, Color(0xFF546E7A))),
  _BrandRule(["survey", "poll", "opinion", "reward", "point", "cashback"], ServiceLook(FontAwesomeIcons.clipboardList, Color(0xFFFF9800))),
];

String _normalizeService(String raw) {
  final low = raw.toLowerCase();
  final buf = StringBuffer();
  for (final r in low.runes) {
    final isWord = (r >= 0x61 && r <= 0x7A) ||
        (r >= 0x30 && r <= 0x39) ||
        (r >= 0x400 && r <= 0x4FF);
    buf.write(isWord ? String.fromCharCode(r) : ' ');
  }
  return buf.toString().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');
}

ServiceLook? _resolveRules(List<_BrandRule> rules, String norm, List<String> toks) {
  for (final rule in rules) {
    for (final key in rule.keys) {
      if (key.startsWith('=')) {
        if (toks.contains(key.substring(1))) return rule.look;
        continue;
      }
      if (key.contains(' ')) {
        if (norm.contains(key)) return rule.look;
        continue;
      }
      if (toks.contains(key)) return rule.look;
      if (key.length >= 5 && toks.any((t) => t.endsWith(key))) return rule.look;
      if (key.length >= 4 && toks.any((t) => t.startsWith(key))) return rule.look;
    }
  }
  return null;
}

final Map<String, ServiceLook> _serviceLookCache = <String, ServiceLook>{};

ServiceLook getServiceLook(String code, [String name = '']) {
  final cacheKey = '$code|$name';
  final cached = _serviceLookCache[cacheKey];
  if (cached != null) return cached;
  // Prefer the human readable name; fall back to the code so legacy
  // getServiceIcon('wa') style calls keep working.
  final norm = _normalizeService(name.trim().isEmpty ? code : name);
  final toks = norm.isEmpty ? const <String>[] : norm.split(' ');
  final look = _resolveRules(_brandRules, norm, toks) ??
      _resolveRules(_categoryRules, norm, toks) ??
      const ServiceLook(FontAwesomeIcons.globe, Color(0xFF9E9E9E));
  _serviceLookCache[cacheKey] = look;
  return look;
}

FaIconData getServiceIcon(String code, [String name = '']) => getServiceLook(code, name).icon;

Color getServiceColor(String code, [String name = '']) => getServiceLook(code, name).color;

// ============== LOGIN / REGISTER SCREEN ==============
class LoginScreen extends StatefulWidget {
  /// Optional message shown above the form, e.g. "session expired".
  final String? notice;
  const LoginScreen({super.key, this.notice});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.notice != null) {
      _errorMessage = widget.notice!;
    }
  }

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _referralController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";
  bool _showReferralField = false;

  Future<void> _submit(bool isRegister, {bool withReferral = false}) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final referral = withReferral ? _referralController.text.trim().toUpperCase() : "";

    if (email.isEmpty) { setState(() => _errorMessage = "Please enter your email."); return; }
    if (!email.contains("@") || !email.contains(".")) { setState(() => _errorMessage = "Please enter a valid email address."); return; }
    if (password.isEmpty) { setState(() => _errorMessage = "Please enter a password."); return; }
    if (password.length < 6) { setState(() => _errorMessage = "Password must be at least 6 characters."); return; }
    if (withReferral && referral.isEmpty) { setState(() => _errorMessage = "Please enter the referral code."); return; }

    setState(() { _isLoading = true; _errorMessage = ""; });
    final endpoint = isRegister ? '/api/register' : '/api/login';
    final url = Uri.parse('https://grizzly-sms-backend.onrender.com$endpoint');
    
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password, "referral_code": referral}),
      ).timeout(const Duration(seconds: 90));
      
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        data = {"detail": "Unexpected server response (${response.statusCode})."};
      }

      final rawId = data['user_id'] ?? data['id'];
      final int? userId = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
      final String userEmail = (data['email'] ?? email).toString();

      if (response.statusCode == 200) {
        // Save the login token first: every later request proves identity
        // with it, and the server no longer trusts a user id from the app.
        await ApiAuth.saveFromResponse(data);

        // Save session for Auto-Login
        try {
          final prefs = await SharedPreferences.getInstance();
          if (userId != null) await prefs.setInt('user_id', userId);
          await prefs.setString('user_email', userEmail);
        } catch (e) {
          print("Could not save session: $e");
        }

        if (isRegister) {
          await http.post(
            Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/request-code'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email": email}),
          );
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => VerifyEmailScreen(email: email)));
        } else {
          if (data['is_verified'] == false) {
            await http.post(
              Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/request-code'),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"email": email}),
            );
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => VerifyEmailScreen(email: email)));
          } else {
            if (userId == null) {
              setState(() => _errorMessage = "Login worked but the server did not return a user id. Please try again.");
            } else if (mounted) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen(userId: userId, email: userEmail)));
            }
          }
        }
      } else {
        setState(() => _errorMessage = fbgClean(data['detail'],
            fallback: "Something went wrong (${response.statusCode})."));
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _errorMessage = "Server is waking up (Render sleeps when idle). Wait ~30 seconds and tap again.");
      }
    } catch (e) {
      final reason = e.toString().split('\n').first;
      if (mounted) {
        setState(() => _errorMessage = "Connection failed: $reason");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPassword() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Reset Password", style: TextStyle(color: Color(0xFF00FF41))),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Enter your email"),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Send Code"),
          ),
        ],
      ),
    );

    if (email != null && email.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/forgot-password'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"email": email}),
        );
        if (res.statusCode == 200) {
          if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => ResetPasswordScreen(email: email)));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email not found"), backgroundColor: Colors.red));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection error"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/icon.png'),
            fit: BoxFit.cover,
            opacity: 0.15,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sms, size: 80, color: Color(0xFF00FF41)),
                const SizedBox(height: 20),
                const Text("FBG SMS", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00FF41), letterSpacing: 2)),
                const SizedBox(height: 40),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 15),
                TextField(controller: _passwordController, decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)), obscureText: true),
                if (_showReferralField) ...[
                  const SizedBox(height: 15),
                  TextField(
                    controller: _referralController,
                    decoration: const InputDecoration(
                      labelText: "Referral Code",
                      hintText: "FBG-XXXXXX",
                      prefixIcon: Icon(Icons.card_giftcard, color: Colors.orange),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPassword,
                    child: const Text("Forgot Password?", style: TextStyle(color: Colors.grey)),
                  ),
                ),
                if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                if (_isLoading) const CircularProgressIndicator(color: Color(0xFF00FF41)),
                if (!_isLoading) ...[
                  ElevatedButton(onPressed: () => _submit(false), style: ElevatedButton.styleFrom(minimumSize: const Size(250, 50)), child: const Text("Login")),
                  const SizedBox(height: 10),
                  if (!_showReferralField)
                    OutlinedButton.icon(
                      onPressed: () => _submit(true),
                      icon: const Icon(Icons.person_add),
                      label: const Text("Create Account"),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(250, 50)),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _submit(true, withReferral: true),
                      icon: const Icon(Icons.card_giftcard),
                      label: const Text("Create Account with Referral"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(250, 50),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() {
                      _showReferralField = !_showReferralField;
                      _errorMessage = "";
                    }),
                    child: Text(
                      _showReferralField ? "Back to normal signup" : "Have a referral code? Tap here",
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============== VERIFY EMAIL SCREEN ==============
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) { setState(() => _errorMessage = "Enter the 6-digit code."); return; }

    setState(() { _isLoading = true; _errorMessage = ""; });
    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/verify-code'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.email, "code": code}),
      );
      if (res.statusCode == 200) {
        // If the backend chooses to hand out a token at this step, keep it.
        try {
          final vdata = jsonDecode(res.body);
          if (vdata is Map<String, dynamic>) await ApiAuth.saveFromResponse(vdata);
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account Verified! Please log in."), backgroundColor: Colors.green));
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() => _errorMessage = fbgClean(data['detail'], fallback: "Invalid code"));
      }
    } catch (e) {
      setState(() => _errorMessage = "Connection failed.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread, size: 80, color: Color(0xFF00FF41)),
              const SizedBox(height: 20),
              Text("We sent a code to ${widget.email}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: "6-Digit Code"),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              if (_isLoading) const CircularProgressIndicator(color: Color(0xFF00FF41)),
              if (!_isLoading)
                ElevatedButton(
                  onPressed: _verify,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(250, 50)),
                  child: const Text("Verify & Continue"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== RESET PASSWORD SCREEN ==============
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";

  Future<void> _reset() async {
    final code = _codeController.text.trim();
    final newPass = _passController.text;

    if (code.isEmpty || newPass.length < 6) {
      setState(() => _errorMessage = "Enter code and a password (min 6 chars).");
      return;
    }

    setState(() { _isLoading = true; _errorMessage = ""; });
    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/auth/reset-password'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.email, "code": code, "new_password": newPass}),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password Reset! Please log in."), backgroundColor: Colors.green));
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() => _errorMessage = fbgClean(data['detail'], fallback: "Invalid code"));
      }
    } catch (e) {
      setState(() => _errorMessage = "Connection failed.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_reset, size: 80, color: Color(0xFF00FF41)),
              const SizedBox(height: 20),
              Text("Enter the code sent to ${widget.email}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: "6-Digit Code"),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passController,
                decoration: const InputDecoration(labelText: "New Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty) Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              if (_isLoading) const CircularProgressIndicator(color: Color(0xFF00FF41)),
              if (!_isLoading)
                ElevatedButton(
                  onPressed: _reset,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(250, 50)),
                  child: const Text("Reset Password"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============== SHARED APP STATE ==============
class ActiveNumber {
  final String activationId;
  final String phoneNumber;
  final String service;
  final String serviceLabel;
  final int country;
  final String countryLabel;
  final int totalSeconds;
  int secondsRemaining;
  String smsCode;
  bool expired = false;
  bool isCancelled = false;
  int failedChecks = 0;
  String notice = "";

  Timer? countdownTimer;
  Timer? pollingTimer;
  Timer? timeoutTimer;

  ActiveNumber({
    required this.activationId,
    required this.phoneNumber,
    required this.service,
    this.serviceLabel = "",
    required this.country,
    this.countryLabel = "",
    this.totalSeconds = 420,
    int? secondsLeft,
    this.smsCode = "",
  }) : secondsRemaining = secondsLeft == null
            ? totalSeconds
            : (secondsLeft < 0
                ? 0
                : (secondsLeft > totalSeconds ? totalSeconds : secondsLeft));

  bool get hasCode => smsCode.isNotEmpty;

  String get displayService {
    if (serviceLabel.isNotEmpty) return serviceLabel;
    final cleaned = service.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (cleaned.isEmpty) return service;
    return cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  void disposeTimers() {
    countdownTimer?.cancel();
    pollingTimer?.cancel();
    timeoutTimer?.cancel();
  }
}

class MainAppState extends ChangeNotifier {
  int userId;
  String email;
  double balance = 0.0;
  String referralCode = "";
  int referralCount = 0;
  double referralEarnings = 0.0;
  List<ActiveNumber> activeNumbers = [];
  int historyVersion = 0;
  bool isOffline = false;
  void Function(ActiveNumber active)? onSmsReceived;

  MainAppState({required this.userId, required this.email});

  void _noteNetwork(bool ok) {
    if (isOffline == !ok) return;
    isOffline = !ok;
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    try {
      final url = Uri.parse('$kApiBase/api/me');
      final response = await http
          .get(url, headers: ApiAuth.headers())
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        _noteNetwork(true);
        final data = jsonDecode(response.body);
        balance = (data['balance'] ?? 0).toDouble();
        referralCode = data['referral_code'] ?? "";
        referralCount = data['referral_count'] ?? 0;
        referralEarnings = (data['referral_earnings'] ?? 0).toDouble();
        notifyListeners();
      } else if (response.statusCode == 401) {
        ApiAuth.handleUnauthorized();
      }
    } catch (e) {
      _noteNetwork(false);
    }
  }

  Future<void> checkForActiveNumbers() async {
    try {
      final url = Uri.parse('$kApiBase/api/me/active');
      final response = await http
          .get(url, headers: ApiAuth.headers())
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 401) {
        ApiAuth.handleUnauthorized();
        return;
      }
      if (response.statusCode != 200) return;
      _noteNetwork(true);
      final data = jsonDecode(response.body);
      if (data['has_active'] != true) return;
      final List<dynamic> activations = data['activations'] ?? [];
      for (final act in activations) {
        final id = act['activation_id'].toString();
        // Never duplicate a card already on screen after a reconnect.
        if (activeNumbers.any((a) => a.activationId == id)) continue;
        final service = act['service'].toString();
        final restored = ActiveNumber(
          activationId: id,
          phoneNumber: act['phone_number'].toString(),
          service: service,
          serviceLabel: (act['service_name'] ?? act['name'] ?? '').toString(),
          country: int.tryParse('${act['country'] ?? 0}') ?? 0,
          countryLabel: (act['country_name'] ?? '').toString(),
          secondsLeft: _secondsLeftFor(act),
        );
        activeNumbers.add(restored);
        _startTimers(restored);
      }
      notifyListeners();
    } catch (e) {
      _noteNetwork(false);
    }
  }

  /// Works out how long an activation has left, so a page reload does not
  /// restart the countdown at the full window.
  int _secondsLeftFor(dynamic act) {
    for (final key in ['seconds_left', 'expires_in', 'time_left', 'ttl']) {
      final v = int.tryParse('${act[key] ?? ''}');
      if (v != null && v > 0) return v;
    }
    for (final key in ['created_at', 'created', 'purchased_at']) {
      final raw = act[key];
      if (raw == null) continue;
      try {
        DateTime? ts;
        if (raw is num) {
          ts = DateTime.fromMillisecondsSinceEpoch(
              raw > 100000000000 ? raw.toInt() : (raw * 1000).toInt(),
              isUtc: true);
        } else {
          ts = DateTime.tryParse(raw.toString());
        }
        if (ts == null) continue;
        final left = 420 - DateTime.now().toUtc().difference(ts.toUtc()).inSeconds;
        return left;
      } catch (_) {}
    }
    return 420;
  }

  void startNewActivation({
    required String phone,
    required String activationId,
    required String service,
    required int country,
    String serviceName = "",
    String countryName = "",
  }) {
    final newActive = ActiveNumber(
      activationId: activationId,
      phoneNumber: phone,
      service: service,
      serviceLabel: serviceName,
      country: country,
      countryLabel: countryName,
    );
    activeNumbers.add(newActive);
    historyVersion++;
    _startTimers(newActive);
    notifyListeners();
  }

  void _startTimers(ActiveNumber active) {
    active.disposeTimers();

    active.countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (active.isCancelled || active.hasCode || active.expired) {
        timer.cancel();
        return;
      }
      if (active.secondsRemaining > 0) {
        active.secondsRemaining--;
        notifyListeners();
      }
      if (active.secondsRemaining <= 0) {
        timer.cancel();
        _expireActivation(active);
      }
    });

    _schedulePoll(active, first: true);
  }

  void _schedulePoll(ActiveNumber active, {bool first = false}) {
    if (active.isCancelled ||
        active.expired ||
        active.hasCode ||
        active.activationId.isEmpty) {
      return;
    }
    // 3s for the first check, then back off when the server is slow or down.
    const delays = [3, 5, 5, 8, 12, 20];
    int idx = first ? 0 : active.failedChecks + 1;
    if (idx >= delays.length) idx = delays.length - 1;
    active.pollingTimer = Timer(Duration(seconds: delays[idx]), () async {
      await _pollOnce(active);
      _schedulePoll(active);
    });
  }

  Future<void> manualCheck(ActiveNumber active) async {
    active.failedChecks = 0;
    await _pollOnce(active);
    if (!active.hasCode && !active.expired) _schedulePoll(active, first: true);
  }

  Future<void> _pollOnce(ActiveNumber active) async {
    if (active.isCancelled || active.hasCode || active.activationId.isEmpty) {
      return;
    }
    try {
      final url = Uri.parse('$kApiBase/api/check-sms/${active.activationId}');
      final response = await http
          .get(url, headers: ApiAuth.headers())
          .timeout(const Duration(seconds: 15));
      _noteNetwork(true);
      final result = parseSmsResponse(response.body);
      if (result.code != null && result.code!.isNotEmpty) {
        active.smsCode = result.code!;
        active.failedChecks = 0;
        active.notice = "";
        active.disposeTimers();
        historyVersion++;
        notifyListeners();
        onSmsReceived?.call(active);
      } else if (result.fatalMessage != null) {
        // The server says this activation can never deliver a code. Stop
        // polling and explain it, instead of silently waiting out the timer.
        active.notice = result.fatalMessage!;
        active.failedChecks = 0;
        active.isCancelled = true;
        active.disposeTimers();
        historyVersion++;
        notifyListeners();
      } else {
        active.failedChecks = 0;
        notifyListeners();
      }
    } catch (e) {
      active.failedChecks++;
      _noteNetwork(false);
      notifyListeners();
    }
  }

  /// Interprets one /api/check-sms reply. The backend's `status` field is
  /// usually a plain upstream status string, but on failure it carries an
  /// escaped JSON document (for example
  /// {"status":"{\"title\":\"NOT_FOUND\",\"details\":\"Activation Not Found\"}"}),
  /// so both shapes have to be understood.
  static SmsPollResult parseSmsResponse(String body) {
    if (body.trim().isEmpty) return const SmsPollResult();
    final trimmed = body.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        var status = (decoded['status'] ?? '').toString().trim();
        final upper = status.toUpperCase();

        // Error/terminal states: stop polling and tell the customer.
        if (upper.contains('NOT_FOUND') ||
            upper.contains('CANCEL') ||
            upper.contains('BANNED') ||
            upper.contains('UNPROCESSABLE') ||
            upper.contains('NO_ACTIVATION')) {
          var detail = status;
          try {
            final inner = jsonDecode(status);
            if (inner is Map) {
              detail = (inner['details'] ?? inner['title'] ?? status).toString();
            }
          } catch (_) {}
          return SmsPollResult(fatalMessage: fbgClean(detail));
        }

        if (upper.contains('STATUS_OK')) {
          for (final key in ['code', 'sms_code', 'smsCode', 'text', 'message']) {
            final v = decoded[key];
            if (v == null) continue;
            final m = RegExp(r'\d{3,8}').firstMatch(v.toString());
            if (m != null) return SmsPollResult(code: m.group(0));
          }
          final m = RegExp(r'\d{3,8}').firstMatch(trimmed);
          if (m != null) return SmsPollResult(code: m.group(0));
          return const SmsPollResult();
        }

        // Waiting (STATUS_WAIT_CODE / STATUS_WAIT_RETRY / anything unknown).
        return const SmsPollResult();
      }
    } catch (_) {}
    if (trimmed.contains('STATUS_OK')) {
      final m = RegExp(r'\d{3,8}').firstMatch(trimmed);
      if (m != null) return SmsPollResult(code: m.group(0));
    }
    return const SmsPollResult();
  }

  /// Backwards-compatible wrapper returning only the extracted code.
  static String? extractSmsCode(String body) {
    return parseSmsResponse(body).code;
  }

  Future<void> cancelActivation(ActiveNumber active) async {
    if (active.isCancelled) return;
    active.isCancelled = true;
    active.disposeTimers();
    if (active.activationId.isNotEmpty) {
      try {
        await http
            .post(Uri.parse('$kApiBase/api/cancel/${active.activationId}'),
                headers: ApiAuth.headers())
            .timeout(const Duration(seconds: 25));
        _noteNetwork(true);
      } catch (e) {
        _noteNetwork(false);
      }
    }
    activeNumbers.remove(active);
    historyVersion++;
    await refreshBalance();
    notifyListeners();
  }

  Future<void> _expireActivation(ActiveNumber active) async {
    if (active.isCancelled || active.hasCode) return;
    active.expired = true;
    active.isCancelled = true;
    active.disposeTimers();
    historyVersion++;
    notifyListeners();
    if (active.activationId.isNotEmpty) {
      try {
        await http
            .post(Uri.parse('$kApiBase/api/cancel/${active.activationId}'),
                headers: ApiAuth.headers())
            .timeout(const Duration(seconds: 25));
        _noteNetwork(true);
      } catch (e) {
        _noteNetwork(false);
      }
    }
    await refreshBalance();
    notifyListeners();
  }

  void clearActive(ActiveNumber active) {
    activeNumbers.remove(active);
    active.disposeTimers();
    historyVersion++;
    notifyListeners();
  }

  String formatTime(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final m = (safe ~/ 60).toString();
    final s = (safe % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  void dispose() {
    for (var active in activeNumbers) {
      active.disposeTimers();
    }
    super.dispose();
  }
}

// ============== HOME SCREEN ==============
class HomeScreen extends StatefulWidget {
  final int userId;
  final String email;
  const HomeScreen({super.key, required this.userId, required this.email});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  late MainAppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = MainAppState(userId: widget.userId, email: widget.email);
    _appState.onSmsReceived = _handleSmsReceived;
    _appState.refreshBalance();
    _appState.checkForActiveNumbers();
  }

  /// Fires the moment a code lands: copy it, buzz, and tell the user.
  Future<void> _handleSmsReceived(ActiveNumber active) async {
    try {
      await Clipboard.setData(ClipboardData(text: active.smsCode));
    } catch (_) {}
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Code ${active.smsCode} received - copied to clipboard"),
        backgroundColor: const Color(0xFF00FF41),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: "VIEW",
          textColor: Colors.black,
          onPressed: () => setState(() => _currentTab = 1),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('FBG SMS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            actions: [
              Center(child: Text("💰 \$${_appState.balance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00FF41)))),
              const SizedBox(width: 10),
            ],
          ),
          body: Column(
            children: [
              if (_appState.isOffline)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade900,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "No connection - retrying automatically",
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentTab,
                  children: [
                    HomeTab(appState: _appState),
                    MyNumbersTab(appState: _appState),
                    ProfileTab(appState: _appState),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (index) {
              setState(() => _currentTab = index);
              if (index == 0) _appState.refreshBalance();
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
              BottomNavigationBarItem(icon: Icon(Icons.phone_android), label: "My Numbers"),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
            ],
          ),
        );
      },
    );
  }
}

// ============== HOME TAB ==============
class HomeTab extends StatefulWidget {
  final MainAppState appState;
  const HomeTab({super.key, required this.appState});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _searchQuery = "";
  String _selectedCategory = "All";
  bool _isLoading = true;
  String _errorMessage = "";
  List<Map<String, String>> _allServices = [];
  Map<int, String> _countries = {};
  bool _countriesLoaded = false;

  final List<String> _popularCodes = ["wa", "tg", "fb", "ig", "lf", "go", "tw", "ds", "ub", "am"];

  final Map<String, List<String>> _categoryKeywords = {
    "Messengers": ["whatsapp", "telegram", "wechat", "chat", "signal", "viber"],
    "Social": ["facebook", "instagram", "tiktok", "twitter", "reddit", "snapchat", "threads", "douyin"],
    "Google": ["google", "gmail", "youtube"],
    "Entertainment": ["netflix", "spotify", "twitch", "ticketmaster"],
    "Shopping": ["amazon", "shopee", "ebay", "aliexpress", "etsy"],
    "Gaming": ["discord", "steam", "roblox", "epic"],
    "Dating": ["tinder", "bumble", "hinge", "badoo"],
    "Finance": ["paypal", "revolut", "wise", "cash"],
  };

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  String _categorize(String name) {
    final lower = name.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) return entry.key;
      }
    }
    return "Other";
  }

  Future<void> _loadServices() async {
    setState(() { _isLoading = true; _errorMessage = ""; });
    try {
      final response = await http.get(Uri.parse('https://grizzly-sms-backend.onrender.com/api/services'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> list = data['services'] ?? [];
        final services = list.map((s) {
          final code = s['code'].toString();
          final name = s['name'].toString();
          return <String, String>{
            "code": code,
            "name": name,
            "category": _categorize(name),
          };
        }).toList();

        services.sort((a, b) {
          final aPop = _popularCodes.indexOf(a["code"]!);
          final bPop = _popularCodes.indexOf(b["code"]!);
          if (aPop != -1 && bPop != -1) return aPop.compareTo(bPop);
          if (aPop != -1) return -1;
          if (bPop != -1) return 1;
          return a["name"]!.compareTo(b["name"]!);
        });

        setState(() { _allServices = services; _isLoading = false; });
      } else {
        setState(() { _errorMessage = "Could not load services."; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = "Connection failed. Is the server running?"; _isLoading = false; });
    }
  }

  Future<void> _loadCountriesOnce() async {
    if (_countriesLoaded) return;
    try {
      final response = await http.get(Uri.parse('https://grizzly-sms-backend.onrender.com/api/countries'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        Map<int, String> loaded = {};
        data.forEach((key, value) {
          if (value is Map) {
            final int countryId = int.parse(key);
            final String countryName = (value['eng'] ?? value['rus'] ?? "Country $key").toString();
            
            if (countryId == 1 || value['visible'] == 1 || value['visible'] == null) {
              loaded[countryId] = countryName;
            }
          }
        });
        _countries = loaded;
        _countriesLoaded = true;
      }
    } catch (e) {}
  }

  List<Map<String, String>> get _filteredServices {
    return _allServices.where((s) {
      final matchCategory = _selectedCategory == "All" || s["category"] == _selectedCategory;
      final matchSearch = _searchQuery.isEmpty ||
          s["name"]!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s["code"]!.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchCategory && matchSearch;
    }).toList();
  }

  Future<void> _onServiceTap(String serviceKey, String serviceName) async {
    await _loadCountriesOnce();

    Map<int, double> prices = {};
    try {
      final pResp = await http.get(Uri.parse('https://grizzly-sms-backend.onrender.com/api/prices?service=$serviceKey'));
      if (pResp.statusCode == 200) {
        final data = jsonDecode(pResp.body);
        data.forEach((countryCode, serviceData) {
          if (serviceData[serviceKey] != null) {
            prices[int.parse(countryCode)] = (serviceData[serviceKey]['cost'] as num).toDouble();
          }
        });
      }
    } catch (e) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => CountryPickerSheet(
        countries: _countries,
        popularNames: const ["United States", "United Kingdom", "Indonesia", "India", "Philippines", "Russia", "Nigeria", "South Africa"],
        selectedId: null,
        prices: prices.map((k, v) => MapEntry(k.toString(), v)),
        onSelected: (id, name) async {
          await _buyNumber(serviceKey, serviceName, id);
        },
      ),
    );
  }

  Future<void> _buyNumber(String serviceKey, String serviceName, int country) async {
    try {
      final url = Uri.parse('https://grizzly-sms-backend.onrender.com/api/buy-number');
      final response = await http.post(
        url,
        headers: ApiAuth.headers({"Content-Type": "application/json"}),
        body: jsonEncode({"user_id": widget.appState.userId, "service": serviceKey, "country": country}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        widget.appState.startNewActivation(
          phone: data['phone_number'],
          activationId: data['activation_id'],
          service: serviceKey,
          serviceName: serviceName,
          country: country,
          countryName: _countries[country] ?? "",
        );        await widget.appState.refreshBalance();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$serviceName number bought! Check 'My Numbers' tab."), backgroundColor: Colors.green),
          );
        }
      } else if (response.statusCode == 401) {
        ApiAuth.handleUnauthorized();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Your session expired. Please log in again."), backgroundColor: Colors.red),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        final message = fbgClean(data['detail'],
            fallback: "FBGSMS could not complete this order. Try another country or service.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection failed."), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _filteredServices;
    final Set<String> cats = {"All"};
    for (final s in _allServices) {
      if (s["category"] != null) cats.add(s["category"]!);
    }
    final categories = cats.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: "Search ${_allServices.length} services",
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final cat = categories[i];
              final selected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  selectedColor: const Color(0xFF00FF41),
                  backgroundColor: const Color(0xFF1A1A1A),
                  labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF41)))
              : _errorMessage.isNotEmpty
                  ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
                  : services.isEmpty
                      ? const Center(child: Text("No services found.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          itemCount: services.length,
                          itemBuilder: (context, i) {
                            final s = services[i];
                            final code = s["code"]!;
                            final icon = getServiceIcon(code, s["name"]!);
                            final color = getServiceColor(code, s["name"]!);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Container(
                                  width: 45, height: 45,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: FaIcon(icon, color: color, size: 22),
                                ),
                                title: Text(s["name"]!, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF00FF41)),
                                onTap: () => _onServiceTap(code, s["name"]!),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ============== MY NUMBERS TAB ==============
class MyNumbersTab extends StatefulWidget {
  final MainAppState appState;
  const MyNumbersTab({super.key, required this.appState});
  @override
  State<MyNumbersTab> createState() => _MyNumbersTabState();
}

class _MyNumbersTabState extends State<MyNumbersTab> {
  List<dynamic> _history = [];
  bool _isLoadingHistory = true;
  int _lastHistoryVersion = -1;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChange);
    _loadHistory();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChange);
    super.dispose();
  }

  void _onAppStateChange() {
    if (widget.appState.historyVersion != _lastHistoryVersion) {
      _lastHistoryVersion = widget.appState.historyVersion;
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    final url = Uri.parse('$kApiBase/api/me/history');
    try {
      final response = await http.get(url, headers: ApiAuth.headers());
      if (response.statusCode == 401) {
        ApiAuth.handleUnauthorized();
        return;
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _history = data['history']);
      }
    } catch (e) {} finally { setState(() => _isLoadingHistory = false); }
  }

  Color _statusColor(String status) {
    if (status == "COMPLETED") return const Color(0xFF00FF41);
    if (status == "CANCELLED") return Colors.red;
    return Colors.orange;
  }

  String _statusLabel(String status) {
    if (status == "COMPLETED") return "Used";
    if (status == "CANCELLED") return "Cancelled";
    return "Pending";
  }

  IconData _statusIcon(String status) {
    if (status == "COMPLETED") return Icons.check_circle;
    if (status == "CANCELLED") return Icons.cancel;
    return Icons.hourglass_top;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final a = widget.appState;

        return Column(
          children: [
            if (a.activeNumbers.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 15, 20, 5),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top, size: 20, color: Color(0xFF00FF41)),
                    SizedBox(width: 8),
                    Text("Active Numbers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  ],
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    itemCount: a.activeNumbers.length,
                    itemBuilder: (context, i) {
                      final active = a.activeNumbers[i];
                      return _ActiveNumberCard(active: active, appState: a);
                    },
                  ),
                ),
              ),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 15, 20, 5),
              child: Row(
                children: [
                  Icon(Icons.history, size: 20, color: Color(0xFF00FF41)),
                  SizedBox(width: 8),
                  Text("History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: _isLoadingHistory
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF41)))
                  : _history.isEmpty
                      ? const Center(child: Text("No past numbers yet.", style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            itemCount: _history.length,
                            itemBuilder: (context, i) {
                              final tx = _history[i];
                              final status = tx['status'].toString();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: Icon(_statusIcon(status), color: _statusColor(status), size: 32),
                                  title: Text(tx['phone_number'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _statusColor(status).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text("Service: ${tx['service']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        ],
                                      ),
                                      if (tx['sms_code'] != null && tx['sms_code'].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text("Code: ${tx['sms_code']}", style: const TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold, fontSize: 13)),
                                        ),
                                    ],
                                  ),
                                  trailing: Text("\$${tx['cost']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}


class _ActiveNumberCard extends StatelessWidget {
  final ActiveNumber active;
  final MainAppState appState;
  const _ActiveNumberCard({required this.active, required this.appState});

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF00FF41),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } catch (_) {}
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
    if (context.mounted) _toast(context, "$label copied");
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Cancel this number?"),
        content: Text(
          "The number is released and the price goes back to your balance.\n\n${active.phoneNumber}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep waiting", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Cancel number"),
          ),
        ],
      ),
    );
    if (ok == true) await appState.cancelActivation(active);
  }

  @override
  Widget build(BuildContext context) {
    final hasCode = active.hasCode;
    final expired = active.expired;
    final accent = hasCode
        ? const Color(0xFF00FF41)
        : (expired ? Colors.red : Colors.orange);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasCode
                      ? Icons.mark_email_read
                      : (expired ? Icons.timer_off : Icons.schedule),
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.displayService,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white),
                  ),
                ),
                if (active.countryLabel.isNotEmpty) ...[
                  Text(active.countryLabel,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 8),
                ],
                Text(
                  hasCode
                      ? "RECEIVED"
                      : (expired
                          ? "EXPIRED"
                          : appState.formatTime(active.secondsRemaining)),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: hasCode
                        ? const Color(0xFF00FF41)
                        : (expired
                            ? Colors.red
                            : (active.secondsRemaining > 60
                                ? const Color(0xFF00FF41)
                                : Colors.orange)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    active.phoneNumber,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5),
                  ),
                ),
                IconButton(
                  tooltip: "Copy number",
                  icon: const Icon(Icons.copy, size: 20, color: Color(0xFF00FF41)),
                  onPressed: () => _copy(context, active.phoneNumber, "Number"),
                ),
              ],
            ),
            if (!hasCode && !expired) ...[
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (active.notice.isEmpty)
                    const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00FF41)))
                  else
                    const Icon(Icons.error_outline,
                        size: 15, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      active.notice.isNotEmpty
                          ? active.notice
                          : (active.failedChecks > 0
                              ? "Connection issue - retrying shortly"
                              : "Waiting for SMS - checks run automatically"),
                      style: TextStyle(
                          fontSize: 11,
                          color: active.notice.isNotEmpty
                              ? Colors.orange
                              : Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
            if (hasCode) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF41).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF00FF41).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "SMS CODE",
                            style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.2,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            active.smsCode,
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00FF41),
                                letterSpacing: 3),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: "Copy code",
                      icon: const Icon(Icons.copy_all, color: Color(0xFF00FF41)),
                      onPressed: () => _copy(context, active.smsCode, "Code"),
                    ),
                  ],
                ),
              ),
            ],
            if (expired) ...[
              const SizedBox(height: 10),
              const Text(
                "No SMS arrived in time. The number was released and the price refunded.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (!hasCode && !expired) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => appState.manualCheck(active),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text("Check now"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00FF41),
                        side: const BorderSide(color: Color(0xFF00FF41)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmCancel(context),
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text("Cancel"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => appState.clearActive(active),
                      icon: const Icon(Icons.check),
                      label: Text(hasCode ? "Done" : "Dismiss"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF41),
                          foregroundColor: Colors.black),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============== PROFILE TAB ==============
class ProfileTab extends StatelessWidget {
  final MainAppState appState;
  const ProfileTab({super.key, required this.appState});

  Future<void> _showTopUpDialog(BuildContext context, {String? method}) async {
    final controller = TextEditingController(text: "5");
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Add Funds", style: TextStyle(color: Color(0xFF00FF41))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter amount in USD (min \$1.00):"),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: "\$ ",
              ),
            ),
            const SizedBox(height: 10),
            const Text("For payments under \$20, please use USDT (TRC20) or Litecoin (LTC) on the checkout page to avoid high Bitcoin fees.", style: TextStyle(fontSize: 12, color: Colors.orange)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val >= 1.0) {
                Navigator.pop(context, val);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Minimum is \$1.00"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );

    if (amount == null) return;
    if (!context.mounted) return;

    if (method == "crypto") {
      _showPaymentChoice(context, amount);
    } else if (method == "card") {
      _startNowPayments(context, amount);
    } else {
      _showPaymentChoice(context, amount);
    }
  }

  // Coins enabled on the Apirone account. code | display name | symbol | brand colour
  static const List<List<String>> _cryptoCoins = [
    ["btc", "Bitcoin", "BTC", "0xFFF7931A"],
    ["eth", "Ethereum", "ETH", "0xFF627EEA"],
    ["usdt@trx", "Tether USDT (TRC20)", "USDT", "0xFF26A17B"],
    ["usdc@trx", "USD Coin (TRC20)", "USDC", "0xFF2775CA"],
    ["usdt@eth", "Tether USDT (ERC20)", "USDT", "0xFF26A17B"],
    ["usdc@eth", "USD Coin (ERC20)", "USDC", "0xFF2775CA"],
    ["usdt@bnb", "Tether USDT (BEP20)", "USDT", "0xFF26A17B"],
    ["usdt@ton", "Tether USDT (TON)", "USDT", "0xFF0098EA"],
    ["ltc", "Litecoin", "LTC", "0xFF345D9D"],
    ["bch", "Bitcoin Cash", "BCH", "0xFF8DC351"],
    ["doge", "Dogecoin", "DOGE", "0xFFC2A633"],
    ["trx", "TRON", "TRX", "0xFFE50915"],
    ["bnb", "BNB", "BNB", "0xFFF3BA2F"],
  ];

  void _showPaymentChoice(BuildContext context, double amount) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Pay \$${amount.toStringAsFixed(2)} with",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
              const SizedBox(height: 4),
              const Text(
                "Choose Payment Method",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00FF41)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _startNowPayments(context, amount);
                },
                icon: const Icon(Icons.credit_card, size: 20),
                label: const Text("Card / Crypto checkout (NOWPayments)"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text("or pay with", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _cryptoCoins.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (c, i) {
                    final coin = _cryptoCoins[i];
                    final Color brand = Color(int.parse(coin[3]));
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: brand.withValues(alpha: 0.22),
                        child: Text(
                          coin[2].substring(0, 1),
                          style: TextStyle(color: brand, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(coin[1], style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(coin[2], style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(ctx);
                        _startApirone(context, amount, coin[0]);
                      },
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startNowPayments(BuildContext context, double amount) async {
    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/payment/create-invoice'),
        headers: ApiAuth.headers({"Content-Type": "application/json"}),
        body: jsonEncode({"user_id": appState.userId, "amount": amount}),
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        Map<String, dynamic> data = {};
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) data = decoded;
        } catch (_) {}
        final linkRaw = data['invoice_url'] ?? data['payment_url'] ?? data['url'] ?? data['invoice_link'];
        if (linkRaw == null || linkRaw.toString().isEmpty || linkRaw.toString() == 'null') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("No payment link returned by server: ${res.body}"), backgroundColor: Colors.red),
            );
          }
          return;
        }

        final url = Uri.parse(linkRaw.toString());
        bool opened = false;
        try {
          opened = await launchUrl(url, mode: LaunchMode.externalApplication);
        } catch (e) {
          opened = false;
        }
        if (!opened) {
          if (context.mounted) _showLinkDialog(context, url.toString());
        }
        Future.delayed(const Duration(seconds: 5), () => appState.refreshBalance());
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Invoice failed (${res.statusCode}): ${res.body}"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment error: ${e.toString().split('\n').first}"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _startApirone(BuildContext context, double amount, String currency) async {
    try {
      final res = await http.post(
        Uri.parse('https://grizzly-sms-backend.onrender.com/api/payment/create-btc-invoice'),
        headers: ApiAuth.headers({"Content-Type": "application/json"}),
        body: jsonEncode({"user_id": appState.userId, "amount": amount, "currency": currency}),
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        Map<String, dynamic> data = {};
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) data = decoded;
        } catch (_) {}
        final invoiceUrl = data['invoice_url'] ?? data['invoice-url'] ?? data['payment_url'] ?? data['url'] ?? data['invoice_link'];
        final btcAddress = data['address'];
        final btcAmount = data['amount_btc'];

        if (invoiceUrl != null && invoiceUrl.toString().isNotEmpty) {
          final url = Uri.parse(invoiceUrl.toString());
          bool opened = false;
          try {
            opened = await launchUrl(url, mode: LaunchMode.externalApplication);
          } catch (e) {
            opened = false;
          }
          if (!opened) {
            if (context.mounted) _showLinkDialog(context, invoiceUrl.toString());
          }
          Future.delayed(const Duration(seconds: 5), () => appState.refreshBalance());
        } else if (btcAddress != null) {
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: const Text("Send Bitcoin", style: TextStyle(color: Color(0xFF00FF41))),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Send exactly:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    SelectableText("${btcAmount ?? ''} BTC", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    const Text("To this address:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    SelectableText(btcAddress, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 12),
                    const Text("Your balance will update automatically after confirmation.", style: TextStyle(color: Colors.orange, fontSize: 11)),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close", style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            );
          }
        } else {
          if (context.mounted) _cryptoFallback(context, amount);
        }
      } else {
        // Apirone gateway is misconfigured or down: keep the user able to pay
        // through the working NOWPayments crypto checkout instead of dead-ending.
        if (context.mounted) _cryptoFallback(context, amount);
      }
    } catch (e) {
      if (context.mounted) _cryptoFallback(context, amount);
    }
  }

  Future<void> _cryptoFallback(BuildContext context, double amount) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bitcoin gateway unavailable - opening crypto checkout instead"),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    }
    await _startNowPayments(context, amount);
  }

  void _showLinkDialog(BuildContext context, String link) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Payment Link", style: TextStyle(color: Color(0xFF00FF41))),
        content: SelectableText(
          "Please copy this link and open it in your browser to pay:\n\n$link",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 45,
                backgroundColor: const Color(0xFF00FF41).withValues(alpha: 0.2),
                child: Text(
                  appState.email.isNotEmpty ? appState.email[0].toUpperCase() : "?",
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF00FF41)),
                ),
              ),
              const SizedBox(height: 15),
              Text(appState.email, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white)),
              const SizedBox(height: 30),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text("Wallet Balance", style: TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 10),
                      Text("\$${appState.balance.toStringAsFixed(2)}", style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF00FF41))),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showTopUpDialog(context, method: "crypto"),
                              icon: const Icon(Icons.currency_bitcoin),
                              label: const Text("Crypto"),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showTopUpDialog(context, method: "card"),
                              icon: const Icon(Icons.credit_card),
                              label: const Text("Card"),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                backgroundColor: Colors.grey[800],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                color: const Color(0xFF1A1A1A),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.card_giftcard, color: Colors.orange, size: 28),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text("Refer & Earn", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text("\$0.50 / friend", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      const Text("Share your code with friends. When they sign up, you both get \$0.50!", style: TextStyle(fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F0F0F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                appState.referralCode.isEmpty ? "Loading..." : appState.referralCode,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.orange),
                              onPressed: () {
                                if (appState.referralCode.isNotEmpty) {
                                  Clipboard.setData(ClipboardData(text: appState.referralCode));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Referral code copied!")));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: _statBox("Friends Invited", "${appState.referralCount}", Colors.orange)),
                          const SizedBox(width: 10),
                          Expanded(child: _statBox("Total Earned", "\$${appState.referralEarnings.toStringAsFixed(2)}", const Color(0xFF00FF41))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email_outlined, color: Color(0xFF00FF41)),
                      title: const Text("Email", style: TextStyle(color: Colors.grey)),
                      subtitle: Text(appState.email, style: const TextStyle(color: Colors.white)),
                    ),
                    const Divider(height: 1, color: Colors.grey),
                    ListTile(
                      leading: const Icon(Icons.support_agent, color: Color(0xFF00FF41)),
                      title: const Text("Contact Support", style: TextStyle(color: Colors.grey)),
                      subtitle: const Text("Chat with us on Telegram", style: TextStyle(color: Colors.white70, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () async {
                        final Uri telegramUrl = Uri.parse('https://t.me/FBG_Support');
                        try {
                          await launchUrl(telegramUrl, mode: LaunchMode.externalApplication);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Could not open Telegram."), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ApiAuth.clear();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text("Logout", style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), side: const BorderSide(color: Colors.red)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ============== COUNTRY PICKER BOTTOM SHEET ==============
class CountryPickerSheet extends StatefulWidget {
  final Map<int, String> countries;
  final List<String> popularNames;
  final int? selectedId;
  final Map<String, double> prices;
  final Function(int, String) onSelected;

  const CountryPickerSheet({
    super.key,
    required this.countries,
    required this.popularNames,
    required this.selectedId,
    required this.prices,
    required this.onSelected,
  });

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final popularEntries = <MapEntry<int, String>>[];
    for (final name in widget.popularNames) {
      final match = widget.countries.entries.where((e) => e.value == name).firstOrNull;
      if (match != null) popularEntries.add(match);
    }

    final filtered = _query.isEmpty
        ? widget.countries.entries.toList()
        : widget.countries.entries.where((e) => e.value.toLowerCase().contains(_query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
            const Text("Select Country", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00FF41))),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: "Search countries...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (_query.isEmpty && popularEntries.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 5), child: Text("⭐ Popular", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FF41), fontSize: 14))),
                    ...popularEntries.map((e) => _buildTile(e.key, e.value)),
                    const Divider(thickness: 2),
                    const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 5), child: Text("🌍 All Countries", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14))),
                  ],
                  ...filtered.map((e) => _buildTile(e.key, e.value)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTile(int id, String name) {
    final isSelected = widget.selectedId == id;
    final price = widget.prices[id.toString()];
    final isOutOfStock = price == null;

    return ListTile(
      enabled: !isOutOfStock,
      title: Text(
        name, 
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, 
          color: isOutOfStock 
              ? Colors.grey[600] 
              : (isSelected ? const Color(0xFF00FF41) : Colors.white),
        )
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOutOfStock)
            Text("Out of stock", style: TextStyle(color: Colors.red[300], fontSize: 12))
          else
            Text("\$${(price + 0.20).toStringAsFixed(2)}", style: const TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold, fontSize: 13)),
          
          if (isSelected && !isOutOfStock)
            const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check, color: Color(0xFF00FF41), size: 20)),
        ],
      ),
      selected: isSelected && !isOutOfStock,
      onTap: isOutOfStock ? null : () {
        widget.onSelected(id, name);
        Navigator.pop(context);
      },
    );
  }
}