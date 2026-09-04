// === 文件: lib/domain/entities/tool_config.dart ===
// 编号：F-04 工具目录实体（v1.35.0 由 ToolItem 演进为 JSON 外部化）
// 说明：v1.35.0(UAPI 批量工具集成)：工具目录从硬编码 const 列表演进为
//   JSON 外部化配置（assets/tools/tools.json，启动预加载进 ToolCatalogStore）。
//   - [ToolConfig]：单个工具全部配置（调用路径/参数/展示方式/结果字段映射），
//     取代旧 ToolItem（tool_item.dart 退役，见 T259）；
//   - [ToolResult]：**结果字段映射**（v1.35.0 实测 25 个 UAPI 接口驱动）——
//     成功响应字段名因接口而异，按 displayType 决定取哪些字段渲染；
//   - 纯领域实体，不依赖 UI 框架与存储（Clean Architecture）；
//   - route/homeCardId 由 customRoute/id 派生，不再显式存储。
import 'dart:convert' show jsonEncode;

/// 工具展示分类（C-42 折叠分组；v1.35.0 实测 25 接口覆盖 14 类，
/// poem 诗泉为规划预留，接口到位后补工具条目即可）。
enum ToolCategory {
  game,
  image,
  network,
  random,
  text,
  time,
  translate,
  daily,
  webParse,
  social,
  misc,
  search,
  convert,
  poem,
  status;

  /// JSON 目录中分类节点 id（snake/camel 归一）。
  String get id => switch (this) {
    ToolCategory.webParse => 'webParse',
    _ => name,
  };

  /// 中文展示名（JSON 分类节点缺失时兜底；正常以 JSON name 为准）。
  String get label => switch (this) {
    ToolCategory.game => '游戏',
    ToolCategory.image => '图片',
    ToolCategory.network => '网络',
    ToolCategory.random => '随机',
    ToolCategory.text => '文本',
    ToolCategory.time => '时间',
    ToolCategory.translate => '翻译',
    ToolCategory.daily => '每日',
    ToolCategory.webParse => '网页解析',
    ToolCategory.social => '社交',
    ToolCategory.misc => '杂项',
    ToolCategory.search => '搜索',
    ToolCategory.convert => '转换',
    ToolCategory.poem => '诗词',
    ToolCategory.status => '状态',
  };

  /// 默认分类图标（MiuixIcons.extended name；工具 icon 缺失时兜底）。
  String get icon => switch (this) {
    ToolCategory.game => 'play',
    ToolCategory.image => 'photos',
    ToolCategory.network => 'link',
    ToolCategory.random => 'refresh',
    ToolCategory.text => 'notes',
    ToolCategory.time => 'timer',
    ToolCategory.translate => 'translate',
    ToolCategory.daily => 'months',
    ToolCategory.webParse => 'screenCapture',
    ToolCategory.social => 'community',
    ToolCategory.misc => 'gridView',
    ToolCategory.search => 'search',
    ToolCategory.convert => 'convertFile',
    ToolCategory.poem => 'notes',
    ToolCategory.status => 'info',
  };

  /// 按 id 反查枚举；未知返回 null。
  static ToolCategory? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final ToolCategory c in ToolCategory.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// 参数控件类型（C-40 动态参数）。
/// 注：JSON type 写作 'switch'，映射到 [toggle]（switch 为 Dart 关键字）。
enum ToolParamType {
  text,
  number,
  select,
  toggle,
  file;

  static ToolParamType fromId(String id) => switch (id) {
    'number' => ToolParamType.number,
    'select' => ToolParamType.select,
    'switch' || 'toggle' => ToolParamType.toggle,
    'file' => ToolParamType.file,
    _ => ToolParamType.text,
  };
}

/// 结果展示类型（C-41 模板分发；custom 走定制页）。
enum ResponseDisplayType {
  image,
  text,
  json,
  list,
  keyValue,
  custom;

  static ResponseDisplayType fromId(String id) => switch (id) {
    'image' => ResponseDisplayType.image,
    'json' => ResponseDisplayType.json,
    'list' => ResponseDisplayType.list,
    'keyValue' => ResponseDisplayType.keyValue,
    'custom' => ResponseDisplayType.custom,
    _ => ResponseDisplayType.text,
  };
}

/// 单个输入参数（名称 = API 参数名；label = 界面展示）。
class ToolParam {
  const ToolParam({
    required this.name,
    required this.label,
    this.type = ToolParamType.text,
    this.placeholder,
    this.options = const <String>[],
    this.defaultValue,
    this.inQuery = false,
  });

  final String name;
  final String label;
  final ToolParamType type;

  /// 占位提示（text/number 用）。
  final String? placeholder;

  /// select 可选项（type=select 时非空）。
  final List<String> options;

  /// 默认值（select/switch/text 均可）。
  final String? defaultValue;

  /// POST 工具中该参数放 **query**（默认 false = 放 JSON body）；
  /// GET 工具恒为 query（本字段忽略）。实测：翻译 to_lang 走 query。
  final bool inQuery;

  factory ToolParam.fromJson(Map<String, dynamic> json) {
    return ToolParam(
      name: json['name'] as String? ?? '',
      label: json['label'] as String? ?? json['name'] as String? ?? '',
      type: ToolParamType.fromId(json['type'] as String? ?? 'text'),
      placeholder: json['placeholder'] as String?,
      options: <String>[
        for (final Object? o in json['options'] as List<Object?>? ?? const <Object?>[])
          if (o != null) o.toString(),
      ],
      defaultValue: json['defaultValue'] as String?,
      inQuery: (json['in'] as String?) == 'query',
    );
  }
}

/// keyValue 模板：单行字段（key = 响应字段名；label = 中文标签）。
class ToolResultField {
  const ToolResultField({required this.key, required this.label});

  final String key;
  final String label;

  factory ToolResultField.fromJson(Map<String, dynamic> json) {
    return ToolResultField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? json['key'] as String? ?? '',
    );
  }
}

/// 结果字段映射（v1.35.0 实测驱动）：成功响应字段因接口而异，
/// 按 [ResponseDisplayType] 使用不同子字段（PLAN §2.1a）：
///   - text:    [field] 取响应该字段文本；
///   - keyValue: [fields] 筛字段 + 中文标签（如农历 20+ 字段只选几个）；
///   - list:    [listPath] 列表字段路径 + [itemTitle]/[itemSubtitle]/[itemUrl]；
///   - image:   [source]='body' 渲染响应字节；='field' 渲染 [imageField] 的 URL；
///   - json:    无字段（原始 JSON 美化展示）。
class ToolResult {
  const ToolResult({
    this.field,
    this.fields = const <ToolResultField>[],
    this.listPath,
    this.itemTitle,
    this.itemSubtitle,
    this.itemUrl,
    this.source,
    this.imageField,
  });

  final String? field;
  final List<ToolResultField> fields;
  final String? listPath;
  final String? itemTitle;
  final String? itemSubtitle;
  final String? itemUrl;

  /// image 来源：'body'（响应字节）| 'field'（响应字段 URL）。
  final String? source;

  /// image 且 source='field' 时的字段名（如 B站 face）。
  final String? imageField;

  factory ToolResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ToolResult();
    return ToolResult(
      field: json['field'] as String?,
      fields: <ToolResultField>[
        for (final Object? o in json['fields'] as List<Object?>? ?? const <Object?>[])
          if (o is Map<String, dynamic>) ToolResultField.fromJson(o),
      ],
      listPath: json['listPath'] as String?,
      itemTitle: json['itemTitle'] as String?,
      itemSubtitle: json['itemSubtitle'] as String?,
      itemUrl: json['itemUrl'] as String?,
      source: json['source'] as String?,
      imageField: json['imageField'] as String?,
    );
  }
}

/// 工具配置（目录单条目；数据源 assets/tools/tools.json）。
/// [category] 冗余存分类（解析时由外层分类节点注入），独立可查。
class ToolConfig {
  const ToolConfig({
    required this.id,
    required this.name,
    required this.summary,
    required this.icon,
    required this.category,
    required this.apiPath,
    this.method = 'GET',
    this.costCredits = 1,
    this.requiresAuth = false,
    this.authHint,
    this.params = const <ToolParam>[],
    this.displayType = ResponseDisplayType.text,
    this.customRoute,
    this.result = const ToolResult(),
  });

  final String id;
  final String name;

  /// 一句说明（入口/首页卡副行）。
  final String summary;

  /// 图标：'custom:steam' 走自绘徽标；其余为 MiuixIcons.extended name。
  final String icon;
  final ToolCategory category;

  /// 相对路径（如 /api/v1/random/string），base 见 AppConstants.uapiBaseUrl。
  final String apiPath;

  /// 'GET'（query 参数）| 'POST'（JSON body，可混合 query）。
  final String method;

  /// 每次调用消耗积分（说明文案；默认 1）。
  final int costCredits;

  /// 是否必须 UAPI key（默认匿名可用）。
  final bool requiresAuth;
  final String? authHint;
  final List<ToolParam> params;
  final ResponseDisplayType displayType;

  /// 定制路由（如 '/steam'）；null → 通用页 `/tool/<id>`。
  final String? customRoute;

  /// 结果字段映射（见 [ToolResult]）。
  final ToolResult result;

  // ── 派生（取代 ToolItem.route / homeCardId）────────────────────────

  /// 点击进入的路由：定制路由优先，否则通用页。
  String get route => customRoute ?? '/tool/$id';

  /// 首页工具卡 id（ToolLaunchCardData.id 一致）。
  String get homeCardId => 'tool_$id';

  factory ToolConfig.fromJson(
    Map<String, dynamic> json, {
    String? categoryId,
  }) {
    return ToolConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      icon: json['icon'] as String? ?? 'tool',
      category:
          ToolCategory.fromId(categoryId ?? json['category'] as String?) ??
          ToolCategory.misc,
      apiPath: json['apiPath'] as String? ?? '',
      method: (json['method'] as String? ?? 'GET').toUpperCase(),
      costCredits: json['costCredits'] as int? ?? 1,
      requiresAuth: json['requiresAuth'] as bool? ?? false,
      authHint: json['authHint'] as String?,
      params: <ToolParam>[
        for (final Object? o in json['params'] as List<Object?>? ?? const <Object?>[])
          if (o is Map<String, dynamic>) ToolParam.fromJson(o),
      ],
      displayType: ResponseDisplayType.fromId(json['displayType'] as String? ?? 'text'),
      customRoute: json['customRoute'] as String?,
      result: ToolResult.fromJson(
        json['result'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'summary': summary,
    'icon': icon,
    'category': category.id,
    'apiPath': apiPath,
    'method': method,
    'costCredits': costCredits,
    'requiresAuth': requiresAuth,
    'authHint': authHint,
    'params': <Map<String, dynamic>>[
      for (final ToolParam p in params) <String, dynamic>{
        'name': p.name,
        'label': p.label,
        'type': p.type.name,
        'placeholder': p.placeholder,
        'options': p.options,
        'defaultValue': p.defaultValue,
        'in': p.inQuery ? 'query' : 'body',
      },
    ],
    'displayType': displayType.name,
    'customRoute': customRoute,
    'result': <String, dynamic>{
      'field': result.field,
      'fields': <Map<String, dynamic>>[
        for (final ToolResultField f in result.fields) <String, dynamic>{
          'key': f.key,
          'label': f.label,
        },
      ],
      'listPath': result.listPath,
      'itemTitle': result.itemTitle,
      'itemSubtitle': result.itemSubtitle,
      'itemUrl': result.itemUrl,
      'source': result.source,
      'imageField': result.imageField,
    },
  };
}

/// 目录分类节点（C-42 折叠面板数据源；顺序 = JSON categories 顺序）。
class ToolCategoryNode {
  const ToolCategoryNode({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.tools,
  });

  final String id;

  /// 界面展示名（如「游戏」）。
  final String name;

  /// 分类图标（MiuixIcons.extended name；JSON 配，缺省回退）。
  final String icon;
  final ToolCategory category;
  final List<ToolConfig> tools;

  factory ToolCategoryNode.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final ToolCategory category =
        ToolCategory.fromId(id) ?? ToolCategory.misc;
    final List<ToolConfig> tools = <ToolConfig>[
      for (final Object? o in json['tools'] as List<Object?>? ?? const <Object?>[])
        if (o is Map<String, dynamic>)
          ToolConfig.fromJson(o, categoryId: id),
    ];
    return ToolCategoryNode(
      id: id,
      name: json['name'] as String? ?? category.label,
      icon: json['icon'] as String? ?? '',
      category: category,
      tools: tools,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'icon': icon,
    'tools': <Map<String, dynamic>>[for (final ToolConfig t in tools) t.toJson()],
  };
}

/// 目录序列化辅助（错误降级时打印诊断用）。
String toolCatalogDebugJson(List<ToolCategoryNode> nodes) =>
    jsonEncode(<Map<String, dynamic>>[for (final ToolCategoryNode n in nodes) n.toJson()]);
