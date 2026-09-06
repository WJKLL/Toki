// lib/core/export/flow_html_exporter.dart
// 编号：D-01 流程图 → 自包含 HTML 可播放文件（v1.44.0 批D）
// 说明：输入 Dashboard.toJson() 字符串，输出单个 .html —— 内嵌 SVG 静态图 +
//       JSON 数据 + 原生 JS 播放器（自动/单步/分支选路/高亮），双击离线可播。
//       - 纯 JSON 解析(无 Dashboard/Flutter 依赖),core 层可独立单测;
//       - 浅色固定语义 token(默认); 自定义色节点/连线用存盘色值;
//       - 连线风格: curve→贝塞尔 / segmented→折线(经 pivots) / rectangular→直角。
import 'dart:convert';

/// HTML 导出器。
class FlowHtmlExporter {
  const FlowHtmlExporter();

  /// ARGB → '#RRGGBB'。
  static String _hex(int v) =>
      '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// 自定义底色上的文字色(按亮度黑/白)。
  static String _fgFor(int argb) {
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    final double lum = (r * 299 + g * 587 + b * 114) / 1000;
    return lum > 150 ? '#000000' : '#FFFFFF';
  }

  /// 导出 HTML 字符串。入参为 [Dashboard.toJson] 或 FlowDoc(version=2) 产物。
  String export(String flowJson) {
    final Map<String, dynamic> data =
        (jsonDecode(flowJson) as Map).cast<String, dynamic>();
    if (data['v'] == 2) return _buildV2(data);
    return _build(data);
  }

  /// v2(FlowDoc)解析:节点(k/x/y/t/note/n/c/color/w/h)→ _El;连线 edges →
  ///   next(分支名 label 作为播放 note,与旧语义一致)。泳道(kind=lane)
  ///   渲染为虚线分区,不进播放数据(与旧 lane 语义一致)。
  String _buildV2(Map<String, dynamic> data) {
    final List<_El> els = <_El>[];
    final Map<String, _El> byId = <String, _El>{};
    for (final dynamic rn in data['nodes'] as List<dynamic>? ?? const <dynamic>[]) {
      final Map<String, dynamic> m = (rn as Map).cast<String, dynamic>();
      final String kind = m['k'] as String? ?? 'step';
      final bool lane = kind == 'lane';
      final bool custom = m['c'] == true;
      final int customColor = (m['color'] as num?)?.toInt() ?? 0;
      final _El e = _El(
        id: m['id'] as String? ?? '',
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        w: lane
            ? ((m['w'] as num?)?.toDouble() ?? 420)
            : switch (kind) {
                'start' || 'end' => 130,
                'decision' => 200,
                _ => 180,
              },
        h: lane
            ? ((m['h'] as num?)?.toDouble() ?? 240)
            : switch (kind) {
                'start' || 'end' => 56,
                'decision' => 84,
                _ => 66,
              },
        text: m['t'] as String? ?? '',
        kind: kind,
        isLane: lane,
        laneTitle: lane ? (m['t'] as String? ?? '') : '',
        note: m['note'] as String? ?? '',
        customColor: custom,
        bg: custom ? _hex(customColor) : '#FFFFFF',
        border: custom ? _hex(customColor) : '#B9BEC7',
        fg: custom
            ? _fgFor(customColor)
            : '#000000',
        textSize: 14,
        next: <_Conn>[],
      );
      els.add(e);
      byId[e.id] = e;
    }
    for (final dynamic re in data['edges'] as List<dynamic>? ?? const <dynamic>[]) {
      final Map<String, dynamic> m = (re as Map).cast<String, dynamic>();
      final _El? src = byId[m['src'] as String? ?? ''];
      final _El? dst = byId[m['dst'] as String? ?? ''];
      if (src == null || dst == null) continue;
      final Map<String, dynamic> d =
          (m['d'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final String label = (d['label'] as String?) ?? '';
      final String note = (d['note'] as String?) ?? '';
      src.next.add(
        _Conn(
          srcId: src.id,
          destId: dst.id,
          note: label.isNotEmpty ? label : note, // 分支名优先(播放显示)。
        ),
      );
    }
    return _render(els);
  }

  /// 公共渲染(旧/v2 共用;元素 → SVG + 播放数据)。
  String _render(List<_El> els) {
    final Map<String, _El> byId = <String, _El>{
      for (final _El e in els) e.id: e,
    };
    final _Lay lay = _Lay(els);
    final StringBuffer nodes = StringBuffer();
    final StringBuffer conns = StringBuffer();
    final List<Map<String, dynamic>> connJs = <Map<String, dynamic>>[];
    for (final _El e in els) {
      if (e.isLane) {
        nodes.writeln(lay.laneSvg(e));
      }
    }
    for (final _El e in els) {
      if (!e.isLane) {
        nodes.writeln(lay.nodeSvg(e));
      }
    }
    for (final _El e in els) {
      for (final _Conn c in e.next) {
        final _El? t = byId[c.destId];
        if (t == null || t.isLane) continue;
        conns.writeln(lay.connSvg(e, t, c));
        connJs.add(<String, dynamic>{
          'srcId': e.id,
          'destId': t.id,
          'note': c.note,
        });
      }
    }
    // 播放器数据结构。
    final StringBuffer js = StringBuffer();
    js.writeln('const DATA=');
    js.writeln(json.encode(<String, dynamic>{
      'els': els.map((e) => e.toJs()).toList(),
      'conns': connJs,
    }));
    js.writeln(';');
    return _html(lay, nodes.toString(), conns.toString(), js.toString());
  }

  String _build(Map<String, dynamic> data) {
    final List<dynamic> rawEls = data['elements'] as List<dynamic>? ?? [];
    final List<_El> els = <_El>[
      for (final dynamic r in rawEls)
        _El.fromMap((r as Map).cast<String, dynamic>()),
    ];
    return _render(els);
  }

  String _html(
    _Lay lay,
    String nodesSvg,
    String connsSvg,
    String dataJs,
  ) {
    final String w = lay.w.toInt().toString();
    final String h = lay.h.toInt().toString();
    return '''<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>流程图演示</title>
<style>
  :root{--ok:#2e7d32;--line:#4a4a4a;--bg:#f7f8fa;--card:#ffffff;}
  *{box-sizing:border-box;margin:0;padding:0;}
  body{background:var(--bg);font-family:"PingFang SC","Microsoft YaHei",system-ui,sans-serif;}
  #wrap{position:relative;margin:14px auto;width:min($w px,calc(100vw - 20px));
    overflow:auto;max-height:calc(100vh - 120px);border-radius:10px;
    box-shadow:0 2px 14px rgba(0,0,0,.12);background:var(--card);}
  svg{display:block;width:100%;height:auto;min-width:$w px;min-height:$h px;}
  .lane{fill:rgba(0,120,255,.045);stroke:#8ab4ff;stroke-dasharray:6 4;}
  .lane-title{fill:#4a6fa5;font-size:12px;font-weight:600;}
  text{user-select:none;}
  .node{cursor:pointer;}
  .node text{pointer-events:none;}
  .step{fill:#ffffff;stroke:#b9bec7;}
  .start{fill:#d3e3fd;stroke:#4a90e2;}
  .end{fill:#ffd9d2;stroke:#e05d52;}
  .decision{fill:#e6ddfc;stroke:#8b6ce0;}
  .node.cur .shape{stroke:#1664ff;stroke-width:3;}
  .node.cur .halo{opacity:.9;}
  .halo{opacity:0;transition:opacity .25s;}
  .line{stroke:var(--line);fill:none;}
  .line.cur{stroke:#1664ff;stroke-width:2.6;filter:drop-shadow(0 0 3px rgba(22,100,255,.55));}
  #bar{position:fixed;left:50%;bottom:12px;transform:translateX(-50%);
    background:var(--card);border:1px solid #d9dee7;border-radius:999px;
    padding:6px 12px;display:flex;gap:8px;align-items:center;box-shadow:0 3px 12px rgba(0,0,0,.16);
    white-space:nowrap;z-index:9;}
  #bar button{border:1px solid #cfd6e1;background:#fff;border-radius:999px;
    min-width:30px;height:30px;cursor:pointer;font-size:14px;color:#333;}
  #bar button.primary{background:#1664ff;border-color:#1664ff;color:#fff;}
  #bar span{font-size:13px;color:#444;max-width:46vw;overflow:hidden;text-overflow:ellipsis;}
  #hint{position:fixed;left:50%;top:12px;transform:translateX(-50%);z-index:10;
    background:rgba(22,100,255,.95);color:#fff;padding:8px 18px;border-radius:999px;
    font-size:14px;display:none;box-shadow:0 3px 10px rgba(0,0,0,.25);}
  #branch{position:fixed;left:50%;top:52px;transform:translateX(-50%);z-index:10;
    background:var(--card);border:1px solid #d9dee7;border-radius:14px;padding:12px 14px;
    box-shadow:0 4px 18px rgba(0,0,0,.18);display:none;min-width:200px;}
  #branch .bt{display:flex;gap:8px;align-items:center;margin:6px 0;cursor:pointer;
    border:1px solid #d9dee7;background:#f2f6ff;border-radius:10px;padding:8px 12px;font-size:14px;}
  #branch .bt:hover{border-color:#1664ff;background:#e5eeff;}
</style>
</head>
<body>
<div id="wrap">
<svg viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" id="svg">
  $connsSvg
  $nodesSvg
</svg>
</div>
<div id="bar">
  <button id="bPlay" class="primary" title="自动播放">▶</button>
  <button id="bStep" title="单步">⏭</button>
  <button id="bReset" title="回到开始">⟲</button>
  <span id="tip"></span>
</div>
<div id="hint"></div>
<div id="branch"></div>
<script>
$dataJs
(function(){
  var els=DATA.els, conns=DATA.conns;
  var svg=document.getElementById('svg'), wrap=document.getElementById('wrap');
  var tip=document.getElementById('tip'), hint=document.getElementById('hint');
  var branch=document.getElementById('branch');
  var bPlay=document.getElementById('bPlay'), bStep=document.getElementById('bStep'),
      bReset=document.getElementById('bReset');
  var byId={}; els.forEach(function(e){byId[e.id]=e;});
  var outs={}; conns.forEach(function(c){ (outs[c.srcId]=outs[c.srcId]||[]).push(c); });
  var cur=null, fromId=null, auto=false, timer=null, done=false;
  var stepCount=0;
  var speed=1200, speeds=[600,1200,2000], si=1;
  function flash(msg){hint.style.display='block';hint.textContent=msg;
    clearTimeout(hint._t);hint._t=setTimeout(function(){hint.style.display='none';},1600);}
  function startEl(){ for(var i=0;i<els.length;i++) if(els[i].kind==='start') return els[i]; return null; }
  function arm(){ clearTimeout(timer); if(auto&&cur) timer=setTimeout(step, speed); }
  function paint(){
    els.forEach(function(e){ var n=document.getElementById('n'+e.id);
      n.classList.toggle('cur', cur&&e.id===cur.id); });
    conns.forEach(function(c){ var l=document.getElementById('c'+c.srcId+'_'+c.destId);
      if(l) l.classList.toggle('cur', fromId&&c.srcId===fromId&&c.destId===(cur?cur.id:''));
    });
    tip.textContent=(cur?cur.text:'')+(fromId?('  · 第 '+stepCount+' 步'):'');
  }
  function go(c){ fromId=(cur?cur.id:null); cur=byId[c.destId]; stepCount++; done=false; paint(); arm(); }
  function stopAuto(){ auto=false; clearTimeout(timer); bPlay.textContent='▶'; }
  function step(){
    if(!cur){ return; }
    if(cur.kind==='end'){ stopAuto(); done=true; paint(); flash('流程结束 ✓'); return; }
    var list=outs[cur.id]||[];
    if(list.length===0){ stopAuto(); done=true; paint(); flash('当前节点无后续连线'); return; }
    if(list.length===1){ go(list[0]); return; }
    // 多出口:暂停自动,弹分支选路。
    var wasAuto=auto; stopAuto(); done=true; paint();
    branch.innerHTML='<div style="font-weight:600;margin-bottom:6px;">选择分支</div>';
    list.forEach(function(c){
      var d=document.createElement('div'); d.className='bt';
      var label=c.note||(byId[c.destId]?byId[c.destId].text:'');
      d.innerHTML='<span style="color:#1664ff">›</span> '+label;
      d.onclick=function(){ branch.style.display='none'; go(c);
        if(wasAuto){ auto=true; bPlay.textContent='⏸'; arm(); } };
      branch.appendChild(d);
    });
    branch.style.display='block';
  }
  bPlay.onclick=function(){
    branch.style.display='none';
    if(done){ done=false; }
    if(!cur){ var s=startEl(); if(!s){flash('请先添加「开始」节点');return;}
      cur=s; stepCount=0; fromId=null; paint(); }
    auto=!auto;
    if(auto){ bPlay.textContent='⏸'; arm(); } else { bPlay.textContent='▶'; clearTimeout(timer); }
  };
  bStep.onclick=function(){
    branch.style.display='none';
    if(!cur){ var s=startEl(); if(!s){flash('请先添加「开始」节点');return;}
      cur=s; stepCount=0; fromId=null; paint(); return; }
    if(done){ done=false; }
    step();
  };
  bReset.onclick=function(){ clearTimeout(timer); auto=false; bPlay.textContent='▶';
    branch.style.display='none'; var s=startEl(); cur=s; stepCount=0; fromId=null;
    done=false; paint(); };
  // 初始:不自动播,仅高亮开始(等待用户操作)。
  var s0=startEl(); if(s0){cur=s0;stepCount=0;paint();}
})();
</script>
</body>
</html>
''';
  }
}

/// 连线数据(JSON 播放器)。
class _Conn {
  _Conn({required this.srcId, required this.destId, required this.note});
  final String srcId;
  final String destId;
  final String note;
}

/// 元素(JSON 解析;字段与 FlowElement.toMap / elementData 兼容)。
class _El {
  _El({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.text,
    required this.kind,
    required this.isLane,
    required this.laneTitle,
    required this.note,
    required this.customColor,
    required this.bg,
    required this.border,
    required this.fg,
    required this.textSize,
    required this.next,
  });

  factory _El.fromMap(Map<String, dynamic> m) {
    final Object? ed = m['elementData'];
    String kind = 'step';
    bool lane = false;
    String note = '';
    bool custom = false;
    String laneTitle = '';
    if (ed is String) {
      kind = ed;
    } else if (ed is Map) {
      final Map e = ed;
      kind = e['k'] as String? ?? 'step';
      lane = e['lane'] == true;
      note = e['note'] as String? ?? '';
      custom = e['c'] == true;
      laneTitle = e['t'] as String? ?? '';
    }
    final double x = (m['positionDx'] as num?)?.toDouble() ?? 0;
    final double y = (m['positionDy'] as num?)?.toDouble() ?? 0;
    final double w = (m['size.width'] as num?)?.toDouble() ?? 160;
    final double h = (m['size.height'] as num?)?.toDouble() ?? 56;
    final List<dynamic> nextRaw = m['next'] as List? ?? [];
    final List<_Conn> next = <_Conn>[];
    for (final dynamic r in nextRaw) {
      final Map c = (r as Map).cast<String, dynamic>();
      next.add(_Conn(
        srcId: m['id'] as String? ?? '',
        destId: c['destElementId'] as String? ?? '',
        note: c['note'] as String? ?? '',
      ));
    }
    String hex(int v) =>
        '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return _El(
      id: m['id'] as String? ?? '',
      x: x,
      y: y,
      w: w,
      h: h,
      text: m['text'] as String? ?? '',
      kind: kind,
      isLane: lane,
      laneTitle: laneTitle.isEmpty ? (m['text'] as String? ?? '') : laneTitle,
      note: note,
      customColor: custom,
      bg: hex((m['backgroundColor'] as num?)?.toInt() ?? 0xFFFFFFFF),
      border: hex((m['borderColor'] as num?)?.toInt() ?? 0xFFB9BEC7),
      fg: hex((m['textColor'] as num?)?.toInt() ?? 0xFF000000),
      textSize: (m['textSize'] as num?)?.toDouble() ?? 14,
      next: next,
    );
  }

  final String id;
  final double x, y, w, h;
  final String text;
  final String kind;
  final bool isLane;
  final String laneTitle;
  final String note;
  final bool customColor;
  final String bg, border, fg;
  final double textSize;
  final List<_Conn> next;

  Map<String, dynamic> toJs() => <String, dynamic>{
        'id': id,
        'text': text,
        'kind': kind,
      };
}

/// 布局:统一平移使坐标为正;计算画布尺寸。
class _Lay {
  _Lay(List<_El> els) {
    double minX = 0, minY = 0, maxX = 0, maxY = 0;
    for (final _El e in els) {
      minX = minX < e.x ? minX : e.x;
      minY = minY < e.y ? minY : e.y;
      maxX = maxX > e.x + e.w ? maxX : e.x + e.w;
      maxY = maxY > e.y + e.h ? maxY : e.y + e.h;
    }
    if (els.isEmpty) {
      w = 800;
      h = 600;
      return;
    }
    w = maxX - minX + 220;
    h = maxY - minY + 220;
    ox = -minX + 110;
    oy = -minY + 110;
  }

  double ox = 0, oy = 0, w = 0, h = 0;

  double px(double x) => x + ox;
  double py(double y) => y + oy;

  String laneSvg(_El e) {
    final double rx = px(e.x), ry = py(e.y);
    return '<g class="lane"><rect x="$rx" y="$ry" width="${e.w}" height="${e.h}" rx="10"/>'
        '<text class="lane-title" x="${rx + 12}" y="${ry + 20}">${_esc(e.laneTitle)}</text></g>';
  }

  String nodeSvg(_El e) {
    final double cx = px(e.x) + e.w / 2;
    final double cy = py(e.y) + e.h / 2;
    final double x = px(e.x), y = py(e.y);
    final String shapeClass = e.customColor
        ? 'step'
        : switch (e.kind) {
            'start' => 'start',
            'end' => 'end',
            'decision' => 'decision',
            _ => 'step',
          };
    // 自定义色:形状直接内联存盘色(覆盖语义 class);否则用语义色。
    final String fillAttr = e.customColor ? ' fill="${e.bg}"' : '';
    final String strokeAttr = e.customColor ? ' stroke="${e.border}"' : '';
    final String shape;
    if (e.kind == 'decision') {
      final double d = e.w * 0.55;
      shape =
          '<path class="shape"$fillAttr$strokeAttr d="M $cx ${cy - d / 2} L ${cx + d / 2} $cy L $cx ${cy + d / 2} L ${cx - d / 2} $cy Z" />';
    } else if (e.kind == 'start' || e.kind == 'end') {
      shape =
          '<rect class="shape"$fillAttr$strokeAttr x="$x" y="$y" width="${e.w}" height="${e.h}" rx="${e.h / 2}"/>';
    } else {
      shape =
          '<rect class="shape"$fillAttr$strokeAttr x="$x" y="$y" width="${e.w}" height="${e.h}" rx="12"/>';
    }
    // 文本一律用元素 text(开始/结束默认即"开始/结束",可被改名)。
    final String label = e.text.isEmpty
        ? switch (e.kind) {
            'start' => '开始',
            'end' => '结束',
            'decision' => '判断',
            _ => '步骤',
          }
        : e.text;
    return '<g class="node $shapeClass" id="n${e.id}">'
        '<rect class="halo" x="${x - 5}" y="${y - 5}" width="${e.w + 10}" height="${e.h + 10}" '
        'rx="16" fill="#1664ff" opacity="0.14"/>'
        '$shape'
        '<text x="$cx" y="$cy" text-anchor="middle" dominant-baseline="central" '
        'font-size="${e.textSize}" fill="${e.customColor ? e.fg : _textColor(shapeClass)}">${_esc(label)}</text>'
        '</g>';
  }

  String connSvg(_El src, _El dst, _Conn c) {
    final double sx = px(src.x) + src.w;
    final double sy = py(src.y) + src.h / 2;
    final double tx = px(dst.x);
    final double ty = py(dst.y) + dst.h / 2;
    final String d =
        'M $sx $sy C ${sx + 40} $sy, ${tx - 40} $ty, $tx $ty';
    return '<path class="line" id="c${src.id}_${dst.id}" d="$d" '
        'stroke-width="2"/>';
  }

  static String _textColor(String cls) => switch (cls) {
        'start' => '#1a4fa0',
        'end' => '#a03a2f',
        'decision' => '#5438a8',
        _ => '#333333',
      };
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
