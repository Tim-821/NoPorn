import 'dart:convert';
import 'dart:io';

const String kDefaultAirportUrl =
    'https://REPLACE_WITH_YOUR_AIRPORT_SUBSCRIPTION_URL';

final _infoNodeRegex = RegExp(
  r'剩余|流量|到期|重置|官网|套餐|网址|过期|联系|群组|公告|更新|订阅|导航',
  caseSensitive: false,
);
final _cleanTagRegex = RegExp(
  r'原生|纯净|家宽|住宅|isp|静态|native|clean|residential',
  caseSensitive: false,
);

/// 直连拉取任意机场订阅（强制带 User-Agent: clash.meta），提取真实节点并自动按
/// 【速度模式（一键最快 + 按国家）】与【纯净模式（固定选死不跳IP + 按国家）】分类，
/// 强行套入锁死的 AdGuard Family + 30万成人拦截 + 夸克直连模板，彻底消灭 COMPATIBLE！
Future<String> fetchAndBuildGuardClashYaml(String airportUrl) async {
  final rawYaml = await _httpGetClashYaml(airportUrl.trim());
  return wrapAirportYamlWithGuardRules(rawYaml);
}

Future<String> _httpGetClashYaml(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (_, __, ___) => true;
  try {
    final uri = Uri.parse(url);
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, 'clash.meta');
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('机场订阅返回 HTTP ${resp.statusCode}');
    }
    return await resp.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

/// 从任意 Clash YAML 中提取 proxies 块并保留原始节点定义（零字段丢失），
/// 同时提取每个节点的 name 做自动地区/纯净分类。
String wrapAirportYamlWithGuardRules(String rawYaml) {
  final lines = const LineSplitter().convert(rawYaml);
  final proxyBlocks = <({String name, List<String> lines})>[];

  bool inProxies = false;
  List<String>? currentBlock;

  void flushBlock() {
    if (currentBlock == null || currentBlock!.isEmpty) return;
    final joined = currentBlock!.join('\n');
    final name = _extractProxyName(joined);
    if (name != null && name.isNotEmpty && !_infoNodeRegex.hasMatch(name)) {
      proxyBlocks.add((name: name, lines: List<String>.from(currentBlock!)));
    }
    currentBlock = null;
  }

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (!inProxies) {
      if (trimmed == 'proxies:' || trimmed.startsWith('proxies:')) {
        inProxies = true;
      }
      continue;
    }

    // 遇到下一个顶层键（无前导空格且包含冒号且不是注释）则 proxies 块结束
    if (rawLine.isNotEmpty &&
        !rawLine.startsWith(' ') &&
        !rawLine.startsWith('\t') &&
        !rawLine.startsWith('#') &&
        !rawLine.startsWith('-')) {
      flushBlock();
      break;
    }

    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    // 单个节点以 "- " 开头
    if (RegExp(r'^\s*-\s+').hasMatch(rawLine)) {
      flushBlock();
      currentBlock = ['  ${trimmed}'];
    } else if (currentBlock != null) {
      currentBlock!.add('    $trimmed');
    }
  }
  flushBlock();

  if (proxyBlocks.isEmpty) {
    throw const FormatException('未能从订阅中解析出有效 Clash 节点（请确认链接支持 Clash/Mihomo 格式）');
  }

  // 去重节点名（防止个别机场重名导致 Mihomo 校验报错）
  final seenNames = <String>{};
  final uniqueBlocks = <({String name, List<String> lines})>[];
  for (final b in proxyBlocks) {
    if (seenNames.add(b.name)) {
      uniqueBlocks.add(b);
    }
  }

  final allNames = [for (final b in uniqueBlocks) b.name];

  // 1. 速度模式：按国家二级分类
  final hkAll = allNames.where((n) => _match(n, r'香港|🇭🇰|\bHK\b|Hong')).toList();
  final jpAll = allNames.where((n) => _match(n, r'日本|🇯🇵|\bJP\b|Japan|东京|大阪')).toList();
  final sgAll = allNames.where((n) => _match(n, r'新加坡|狮城|🇸🇬|\bSG\b|Singapore')).toList();
  final twAll = allNames.where((n) => _match(n, r'台湾|🇹🇼|\bTW\b|Taiwan|台北')).toList();
  final usAll = allNames.where((n) => _match(n, r'美国|🇺🇸|\bUS\b|United States|洛杉矶|硅谷')).toList();
  final assignedSpeed = {...hkAll, ...jpAll, ...sgAll, ...twAll, ...usAll};
  final otherAll = allNames.where((n) => !assignedSpeed.contains(n)).toList();

  // 2. 纯净模式：筛选标注“原生/纯净/家宽”的节点按国家固定选死（不加自动跳转防封号）
  final cleanAll = allNames.where((n) => _cleanTagRegex.hasMatch(n)).toList();
  final usClean = cleanAll.where((n) => _match(n, r'美国|🇺🇸|\bUS\b|United')).toList();
  final jpClean = cleanAll.where((n) => _match(n, r'日本|🇯🇵|\bJP\b|Japan')).toList();
  final hkClean = cleanAll.where((n) => _match(n, r'香港|🇭🇰|\bHK\b|Hong')).toList();
  final twClean = cleanAll.where((n) => _match(n, r'台湾|🇹🇼|\bTW\b|Taiwan')).toList();
  final assignedClean = {...usClean, ...jpClean, ...hkClean, ...twClean};
  final otherClean = cleanAll.where((n) => !assignedClean.contains(n)).toList();

  // 顶层极简 2 标签：
  // 1. 速度（第1项 ⚡ 最快，下方直接按 香港->日本->新加坡->台湾->美国->其他 排整齐，一层直达不套娃）
  // 2. 纯净（直接按 美国->日本->台湾->香港->其他 排整齐原生IP，纯手动固定不乱跳）
  final orderedSpeedNodes = <String>[
    '⚡ 最快',
    ...hkAll,
    ...jpAll,
    ...sgAll,
    ...twAll,
    ...usAll,
    ...otherAll,
  ];

  final orderedCleanNodes = <String>[
    ...usClean,
    ...jpClean,
    ...twClean,
    ...hkClean,
    ...otherClean,
  ];
  if (orderedCleanNodes.isEmpty) {
    orderedCleanNodes.addAll([
      ...usAll,
      ...jpAll,
      ...sgAll,
      ...twAll,
      ...hkAll,
      ...otherAll,
    ]);
  }

  final buf = StringBuffer();
  buf.writeln('''
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: false

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: redir-host
  respect-rules: false
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://family.adguard-dns.com/dns-query
    - tls://family.adguard-dns.com
  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query
    - 223.5.5.5
  nameserver-policy:
    "geosite:cn,private":
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query
    "+.quark.cn":
      - https://dns.alidns.com/dns-query
    "+.uc.cn":
      - https://dns.alidns.com/dns-query
    "+.ucweb.com":
      - https://dns.alidns.com/dns-query
    "+.sm.cn":
      - https://dns.alidns.com/dns-query
  fallback:
    - https://family.adguard-dns.com/dns-query
    - tls://family.adguard-dns.com
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:''');

  for (final b in uniqueBlocks) {
    for (final line in b.lines) {
      buf.writeln(line);
    }
  }

  buf.writeln('\nproxy-groups:');
  _writeSelectGroup(buf, '速度', orderedSpeedNodes);
  _writeSelectGroup(buf, '纯净', orderedCleanNodes);

  // 隐藏底层 url-test 组，使其不占顶栏标签，仅作为“速度”里的第 1 项按钮
  buf.writeln('  - name: "⚡ 最快"');
  buf.writeln('    type: url-test');
  buf.writeln('    hidden: true');
  buf.writeln('    url: https://www.gstatic.com/generate_204');
  buf.writeln('    interval: 300');
  buf.writeln('    tolerance: 50');
  buf.writeln('    proxies:');
  for (final n in allNames) {
    buf.writeln('      - ${_yamlQuote(n)}');
  }

  buf.writeln('''

rule-providers:
  nsfw-oisd:
    type: http
    behavior: domain
    format: text
    url: "https://nsfw.oisd.nl/domainswild2"
    path: ./ruleset/nsfw-oisd.txt
    interval: 86400

rules:
  - IP-CIDR,0.0.0.0/32,REJECT,no-resolve
  - DOMAIN,dns.google,REJECT
  - DOMAIN,dns.google.com,REJECT
  - DOMAIN,cloudflare-dns.com,REJECT
  - DOMAIN,mozilla.cloudflare-dns.com,REJECT
  - DOMAIN,one.one.one.one,REJECT
  - DOMAIN,dns.quad9.net,REJECT
  - DOMAIN,dns.opendns.com,REJECT
  - DOMAIN-SUFFIX,doh.opendns.com,REJECT
  - RULE-SET,nsfw-oisd,REJECT
  - GEOSITE,category-porn,REJECT
  - DOMAIN-SUFFIX,anthropic.com,纯净
  - DOMAIN-SUFFIX,claude.ai,纯净
  - DOMAIN-SUFFIX,claude.com,纯净
  - DOMAIN-SUFFIX,openai.com,纯净
  - DOMAIN-SUFFIX,chatgpt.com,纯净
  - DOMAIN-SUFFIX,oaistatic.com,纯净
  - DOMAIN-SUFFIX,oaiusercontent.com,纯净
  - DOMAIN-SUFFIX,gemini.google.com,纯净
  - DOMAIN-SUFFIX,generativelanguage.googleapis.com,纯净
  - DOMAIN-SUFFIX,perplexity.ai,纯净
  - GEOSITE,private,DIRECT
  - GEOIP,private,DIRECT,no-resolve
  - DOMAIN-SUFFIX,quark.cn,DIRECT
  - DOMAIN-SUFFIX,uc.cn,DIRECT
  - DOMAIN-SUFFIX,ucweb.com,DIRECT
  - DOMAIN-SUFFIX,sm.cn,DIRECT
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,速度
''');

  return buf.toString();
}

void _writeSelectGroup(StringBuffer buf, String groupName, List<String> items) {
  // 数学级防循环：绝不允许分组里引用与自身同名的节点
  final safeItems = items.where((i) => i != groupName).toList();
  buf.writeln('  - name: ${_yamlQuote(groupName)}');
  buf.writeln('    type: select');
  buf.writeln('    proxies:');
  for (final item in safeItems.isEmpty ? ['DIRECT'] : safeItems) {
    buf.writeln('      - ${_yamlQuote(item)}');
  }
}

bool _match(String text, String pattern) =>
    RegExp(pattern, caseSensitive: false).hasMatch(text);

String? _extractProxyName(String block) {
  // 支持单引号 name: '🇺🇸 美国01'、双引号 name: "xxx" 以及无引号 name: xxx
  final mSingle = RegExp(r"name\s*:\s*'([^']+)'").firstMatch(block);
  if (mSingle != null) return mSingle.group(1)?.trim();
  final mDouble = RegExp(r'name\s*:\s*"([^"]+)"').firstMatch(block);
  if (mDouble != null) return mDouble.group(1)?.trim();
  final mBare = RegExp(r'name\s*:\s*([^,\}\r\n]+)').firstMatch(block);
  if (mBare != null) return mBare.group(1)?.trim();
  return null;
}

String _yamlQuote(String s) {
  final escaped = s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$escaped"';
}
