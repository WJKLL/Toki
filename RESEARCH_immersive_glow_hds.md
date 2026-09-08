# 璋冪爺:娌夋蹈鍏夋劅(HDS)鍙傛暟瀵归綈鍒嗘瀽

> 2026-07 璋冪爺,浠呰緭鍑哄垎鏋?**鏈惤鍦颁换浣曚唬鐮?*銆?> 鑳屾櫙:璇勪及 Flutter 渚ф帴鍏ラ缚钂?娌夋蹈鍏夋劅"鐨勫彲琛屾€с€傝皟鐮斿璞′负绀惧尯鍖?> `harmony_immersive_glow`(GitCode,绾?Dart 杩戜技)涓?`ohos_immersive_light`(鍘熺敓鎻掍欢鑼冧緥)銆?> 缁撹鍏堣:**绯荤粺绾у厜鎰熸棤娉曟帴鍏?缁勪欢绾?HDS 绯荤粺鏉愯川浠呭師鐢熷彲鐢?Flutter 渚у敮涓€鐜板疄璺緞 =
> 鑷粯杩戜技,涓旀湰椤圭洰宸叉湁 80% 鍩虹璁炬柦(蹇収/棰勬ā绯?鎶樺皠/鍙屽嘲楂樺厜),宸窛闆嗕腑鍦?鍏夋睜/鎵厜/浜や簰鍏夊湀"涓?鑳藉姏闂ㄧ鍒嗙骇"銆?*

---

## 1. 浜嬪疄鏍稿疄(鏉ユ簮)

| 椤?| 鏍稿疄缁撴灉 |
|---|---|
| `harmony_immersive_glow` | 鉁?鐪熷疄瀛樺湪銆侴itCode `ZuoYueLiang/harmony_immersive_glow_tabbar`(MIT,绾?Dart,git 渚濊禆,鏃?pub 鍙戝竷)銆備綔鑰呰嚜杩?浠?杩戜技",**涓嶆槸 ArkUI 绯荤粺鏉愯川 API 鐨勭粦瀹?*;鐪熷疄 HDS 鐢?`@kit.UIDesignKit` 鎻愪緵 |
| `ohos_immersive_light` | 鉁?鐪熷疄瀛樺湪銆侳lutter-OH 鎻掍欢寮€鍙戣寖渚?CSDN 2026-06-05 瀹炴垬鏁欑▼,Windows 韪╁潙:example 涓嶅彲鐢ㄩ渶鑷缓宸ョ▼銆佸繀椤?`path:` 鏈湴渚濊禆) |
| 鍘熺敓鑳藉姏鐪熻韩 | `HdsTabsFloatingStyle.systemMaterialEffect` / 鏍囬鏍?`systemMaterialEffect`(HDS 缁勪欢绾х郴缁熸潗璐?API 23+)+ 闂ㄧ `hdsMaterial.getSystemMaterialTypes()`(鍚?`MaterialType.IMMERSIVE` 鎵嶅厑璁?GENTLE/EXQUISITE,鍚﹀垯鍥為€€ SMOOTH) |
| 涓変釜闄愬埗 | 鉁?鍧囧睘瀹?API 23+銆佸崕涓虹嫭鍗?OpenHarmony 涓嶅彲鐢?銆佺涓夋柟涓嶅彲璋冪郴缁熺骇鍏夋劅鎶樺皠(pointLight 涓?System API) |
| Flutter 渚у樊寮?| 鍘熸枃妗ｆ槑纭?Flutter `BackdropFilter` 涓?ArkUI 绯荤粺鏉愯川**涓嶅湪鍚屼竴鍚堟垚绠＄嚎**,閲囨牱鑼冨洿/杈圭紭瑁佸壀/鑳藉姏闂ㄧ/璁惧绛栫暐鍧囦笉鍚?|

**鍙傝€冧粨搴撳厠闅嗕綅缃?*:`<research-tree>/harmony_immersive_glow/`
鏍稿績鏂囦欢:`lib\harmony_immersive_glow.dart`(1359 琛?銆乣docs\native_hds_compare.md`銆乣README.md`銆?
---

## 2. 鍙傝€冨疄鐜版媶瑙?鍙傛暟鍏ㄨ〃)

### 2.1 绛夌骇 脳 6 鍙傛暟(婧愮爜 `_HarmonyGlowMaterialPainter` / level extension)

| 绛夌骇 | blurSigma | fillOpacity(鐧藉簳) | glowOpacity(鍏夋睜) | shadowOpacity | specularOpacity(鎵厜) | scatterOpacity(鏁ｅ皠) |
|---|---|---|---|---|---|---|
| `smooth` | **8** | .58 | .05 | .08 | .12 | .08 |
| `gentle` | **22** | .30 | .28 | .16 | .38 | **.90** |
| `exquisite` | **34** | .13 | .34 | .24 | .48 | .48 |
| `adaptive` | 22(璺熼殢 gentle) | | | | | |

`adaptive` 鐗规畩:绯荤粺"鍑忓急鍔ㄧ敾"(disableAnimations)鈫?鑷姩瑙ｆ瀽涓?`smooth`,鍚﹀垯 `gentle`銆?
### 2.2 鑳藉姏闂ㄧ(Flutter 渚ч€傞厤)

```dart
harmonyGlowLevelForCapability(supportsImmersiveMaterial, preferExquisite)
// 涓嶆敮鎸?鈫?smooth;鏀寔 鈫?exquisite(鎴?preferExquisite:false 鈫?gentle)
```

- 鍘熺敓渚?`hdsMaterial.getSystemMaterialTypes()` 杩斿洖鍚?`MaterialType.IMMERSIVE` 鎵嶅厑璁?GENTLE/EXQUISITE;
- **Flutter 渚т笉鑳界洿鎺ユ煡璇㈣ ArkUI API**,鍙傝€冨寘閫氳繃瀹夸富娉ㄥ叆(`harmonyGlowLevelForCapability` 鍏ュ弬)瀹炵幇闂ㄧ鈥斺€旀湰椤圭洰 搂9 `plat` 鑳藉姏灞傚凡璁″垝鎵挎媴姝よ亴璐ｃ€?- `HarmonyGlowEffectTuning` 涓?7 涓箻瀛?`blurScale/surfaceScale/glowScale/shadowScale/specularScale/elasticScale/scatterScale`),鍦ㄧ瓑绾у熀纭€涓婁簩娆″井璋?涓嶆敼鍙樼瓑绾ц涔夈€?
### 2.3 璋冭壊鏉?榛樿)

| token | 鍊?| 璇箟 |
|---|---|---|
| `surfaceTint` | `#FFFFFF` | 鏉愯川搴?|
| `edgeHighlight` | `#E6FFFFFF` | 涓?澶栫紭楂樺厜鎻忚竟 |
| `edgeShadow` | `#24000000` | 涓嬬紭/鎶曞奖 |
| `activeColor` | `#1476FF` | 閫変腑鍥炬爣/鏂囧瓧 |
| `inactiveColor` | `#15171A` | 鏈€変腑 |
| `glowColors` | `#72E3C0` / `#7C8DF7` / `#FFC178` | 涓夎壊鍏夋睜(闈掔豢/闈涚传/鐞ョ弨) |

### 2.4 鏉愯川灞傛覆鏌撶粨鏋?姣忓抚)

```
[DecoratedBox: boxShadow(0,12) blur 12|24 脳 shadowScale]
鈹斺攢 ClipRRect
   鈹斺攢 Stack
      鈹溾攢 BackdropFilter(blur 蟽)                    鈫?涓绘ā绯?姣忓抚瀹炴椂
      鈹溾攢 _HarmonyBackdropScatter(scatter>0 鏃?      鈫?3 璺?
      鈹?   鈹溾攢 ImageFilter.matrix 涓績鏀惧ぇ 脳(1+.035c, 1+.012c) + 鐧?tint .028c
      鈹?   鈹溾攢 blur(蟽x=蟽(.65+.32c)鈮?2, 蟽y=蟽(.18+.08c)鈮?6) 骞崇Щ 鈭?c + tint .018c
      鈹?   鈹溾攢 blur(鍚屄废兠?78) 骞崇Щ 鈭?c + tint .014c
      鈹?   鈹斺攢 _ScatterVeilPainter:4 鐧界珫妞渾甯?screen, 鐩镐綅婕傜Щ 卤4px)
      鈹溾攢 CustomPaint(_HarmonyGlowMaterialPainter)
      鈹?   鈹溾攢 鐧藉簳 fill(蟽 fillOpacity脳surfaceScale)
      鈹?   鈹溾攢 鍏夋睜:3 鑹?RadialGradient(plus) 浜害 .38/.1, 鍗婂緞 .55+.08i, 鐩镐綅鍦嗗懆婕傜Щ 9%瀹?12%楂?      鈹?   鈹溾攢 鎵厜:鐧?RadialGradient(screen) 妯悜鎵姩 68%瀹?150%楂?      鈹?   鈹斺攢 杈圭紭:1.1px LinearGradient(椤?.9鈫?2鈫掑簳 .26) + 椤堕珮鍏夌嚎(.7, 12px inset)
      鈹斺攢 Material(transparency) + child
```

### 2.5 浜や簰(鎮诞搴曟爮涓撳睘,鎸夐渶)

鎸夊帇鈫掑厜鍦?3 鑹?caustic + 鐧?lens 楂樺厜)+ 寮圭哀 ticker(stiffness 68+24e / damping 14+4(1-e), 浣嶇疆 clamp 卤1.12,鎷栨嫿 pull clamp 卤.24/.18)+ 鏁翠綋 scale 鎷変几(1+.34H+.035V / 1+.24V鈭?025H);鍥炬爣鎸夊帇 `.88 / 80ms`銆佸洖寮?`elasticOut / 360ms`;鏉炬墜 `interactionFadeDuration 260ms reverse`銆傞€変腑鎬佸垏鎹?*鏁呮剰涓嶅啀琛ョ櫧 flash**(瀵归綈鍘熺敓 HDS 鍙湁鎸夊帇涓湁鐧借壊鍏夊湀)銆?
### 2.6 鎬ц兘鎴愭湰(閲嶈)

姣忓抚鍚?**3 涓?BackdropFilter**(1 涓?+ 2 鏁ｅ皠 blur)+ 1 涓?`ImageFilter.matrix` + 4 甯?CustomPaint,鏃犵紦瀛樷€斺€擿exquisite`(蟽34 + 楂?scatter)鈮?姣忓抚 3 娆￠珮鏂灞?pass,浣庣璁惧婧环鏄庢樉銆俁EADME 鑷堪:浣庣搴斿洖閫€ `smooth`;`BackdropFilter` 闇€鍚庢柟鐪熷疄鍐呭(绾壊鑳屾櫙鏁堟灉寮?銆?
---

## 3. 椤圭洰鐜版湁鑳藉姏鐩樼偣

鍙岀涓€鑷?闀滃儚涓庝富椤圭洰 kernel/shaders **閫愭枃浠跺搱甯?SAME**;闀滃儚浠呭 main.dart shader 棰勭儹):

| 鑳藉姏 | 浣嶇疆 | 鐜扮姸 |
|---|---|---|
| 鑳屾櫙蹇収浣撶郴 | `MiuixLayerBackdrop`(flutter_miuix) | 蹇収 + globalOffset + **pixelRatio 鍙檷閲囨牱**,椹卞姩鍏ㄩ儴鑷爺妯＄硦/鎶樺皠 |
| 棰勬ā绯婄紦瀛?| `kernel/blur.dart` `BackdropBlur`(+ `c27_prefrosted_blur.dart`) | **P0 缂撳瓨**:蹇収/閲囨牱鍖?鍗婂緞涓嶅彉鏃跺鐢ㄦā绯婄汗鐞?姣忓抚浠?drawImageRect鈥斺€斿凡鍦ㄥ垏椤?鎸夊帇涓牴娌绘瘡甯ч珮鏂姈鍔?鍙傝€冨寘鏃犳浼樺寲 |
| 杈圭紭鎶樺皠 | `kernel/lens.dart` `LensRefraction` + `shaders/lens_refraction.frag` | 杈圭紭鎶樺皠(鈭?0dp)/褰╄櫣/娴佸姩/娣卞害,鍙?backdrop(椤甸潰+搴曟爮鐜荤拑);鍙傛暟涓?shader 鍧囧弻绔悓婧?|
| 鍙屽嘲楂樺厜 | `kernel/dual_peak_highlight.dart` + `shaders/bloom_dual_peak.frag` | 鏂瑰悜鍙屽厜(primary/secondary,180掳 瀵瑰嘲),`LightSource` position/intensity/color + innerBlur + blendMode鈥斺€斾笌 HDS"鐐瑰嚮鍏夊湀/楂樺厜"鍚屾瀯 |
| 姣涚幓鐠冪粍浠?| `c22_mask_selection_bar` / `c23_push_collapsing_header` / `c24_frosted_fab` / `c25_frosted_top_bar`(瀹樻柟姣涚幓鐠? | U-03 绛栫暐缁熶竴绠℃帶 |
| 妯＄硦绛栫暐 | `core/utils/u03_blur_policy.dart` | **sigma 鈮?20**銆侀潰绉?鈮?40% 瑙嗗彛銆丄ndroid 13+ 寮€ / Web 绂?**OH 鏃?androidSdkInt(鍒?null)鈫?褰撳墠榛樿鍏佽** |
| 闃诲凹鎷栨嫿 | `kernel/damped_drag.dart` | 宸叉湁(鍙綔寮规€?ticker 鍙傝€? |
| 涓婚 | `main.dart` `_shellTheme` seedColor = `theme.colors.primary`(MiuixThemeData 娲剧敓);Miuix 宸查摵 56 鏂囦欢 | 涓婚 token 鍗曚竴鏉ユ簮 = Miuix |
| shader 棰勭儹 | 浠呴暅鍍?`main.dart` `_warmupShaders`(lens_refraction + bloom_dual_peak) | 涓婚」鐩噿鍔犺浇(棣栨浣跨敤 `FragmentProgram.fromAsset`);Impeller/Vulkan 鍐风紪璇戦娆″崱椤?|
| 鍗＄墖闃村奖 | `card_shell.dart` | 宸叉湁瀹藉睆(鈮?00px)闄嶇骇 tier(blur/offset 鍑忓崐) |

---

## 4. 鑳藉姏瀵圭収鐭╅樀

| # | HDS 鍏夋劅瑕佺礌 | 鍙傝€冨寘瀹炵幇 | 鏈」鐩凡鏈?| 缁撹 |
|---|---|---|---|---|
| 1 | 鑳屾櫙妯＄硦(涓绘潗璐? | BackdropFilter 蟽8鈥?4 | `BackdropBlur` + P0 缂撳瓨 | 鉁?**宸叉湁涓旀洿浼?*(缂撳瓨;蟽 涓婇檺寰?U-03 瑁佸喅) |
| 2 | 鏁ｅ皠/鏀惧ぇ鎰?| matrix 鏀惧ぇ 1.035 + 2 璺?blur 骞崇Щ + 鐧?veil | `LensRefraction`(杈圭紭鎶樺皠,闈炴暣闈㈡斁澶? | 鈿狅笍 閮ㄥ垎:鏁撮潰寰斁澶ч渶鏂?scatter 鑳藉姏(鍙墿 lens shader 鎴栨柊澧炲皬 shader) |
| 3 | 褰╄壊鍏夋睜 | 3 鑹?radial(plus)鐩镐綅婕傜Щ | `DualPeakHighlight`(鏂瑰悜鍏?闈炲厜姹? | 鈿狅笍 闇€鏂?painter(绠€鍗?radial 寰幆,浣庢垚鏈? |
| 4 | 鎵厜/楂樺厜 sweep | 鐧?radial 妯壂(screen) | 闈欐€佸弻宄伴珮鍏?| 鈿狅笍 闇€ animationValue 椹卞姩(鐜版湁 shader 鍙鐢?鎺ュ姩鐢诲嵆鍙? |
| 5 | 杈圭紭鎻忚竟 + 椤跺厜绾?| 1.1px 娓愬彉 + 椤剁嚎 .7 | `inner_shadow`(鏆楄竟) | 鈿狅笍 鏂板楂樺厜杈?灏?painter/閲嶇粯) |
| 6 | 鎸夊帇鍏夊湀(鐧?lens) | 鐧?radial + 寮圭哀 ticker | 鈥?Miuix 鎸夊帇楂樹寒鑳藉姏鏈夐檺) | 鉂?闇€鏂板(浜や簰) |
| 7 | 鎷栨嫿浜岀淮寮规€у舰鍙?| spring ticker + scale 鎷変几 | `damped_drag.dart` | 鈿狅笍 鏈夊熀纭€浠?闇€鎺ュ叆鏉愯川灞?|
| 8 | 鍥炬爣鐐瑰嚮寮规€?| .88 / 80ms, elasticOut 360ms | Miuix 缁勪欢鑷甫 | 鉁?鏃犻渶寮€鍙?|
| 9 | 鑳藉姏闂ㄧ鍒嗙骇 | getSystemMaterialTypes + levelForCapability + disableAnimations | 鈥?搂9 plat capability 璁″垝涓? | 鉂?灞?搂9 `plat_visual_tokens` 鑼冪暣 |

**鑷粯楠ㄦ灦(1/3/4/5)鎬讳唬鐮侀噺棰勪及 鈮?300鈥?00 琛?*(painter + 缁勮),浜や簰(6/7)鍙﹂渶 200鈥?00 琛?+ 鐪熸満鑱旇皟銆?
---

## 5. 鍏抽敭鍐茬獊涓庨闄?
1. **蟽 涓婇檺鍐茬獊**:HDS `exquisite` 蟽34 > U-03 `maxBlurSigma` 20銆偮? 闇€瑁佸喅:OH 鏀寔璁惧鏀惧(36)杩樻槸鎸?U-03 闄嶇骇鍒?gentle(蟽22 浜﹁秴 20,20 浠ュ唴 鈮?浠嬩簬 smooth/gentle)銆?2. **鍚堟垚绠＄嚎宸紓**(鏃犳硶娑堥櫎):`BackdropFilter`/蹇収鍧囬潪 ArkUI 绯荤粺鏉愯川绠＄嚎,閲囨牱鑼冨洿銆佽竟缂樿鍓€佹潗璐ㄧ瓑绾ц涓轰笌鐪熷搧涓嶄竴鑷粹€斺€斿弬鑰冨寘鍘熺敓瀵规瘮椤电敤浜庝汉宸ユ牎鍑?椤圭洰鑻ュ仛,闇€瑕佷竴鍚嶅姣斿熀鍑?寤鸿浣庝紭鍏堢骇)銆?3. **鎬ц兘**:鍙傝€冨寘姣忓抚 3 娆℃ā绯婃棤缂撳瓨;椤圭洰鐢ㄩ妯＄硦缂撳瓨鍙帇鍥?1 娆?**鑻ュ仛鍏夋劅蹇呴』璧扮紦瀛樿矾寰?*,鍚﹀垯杩濊儗 C-27 鏃㈡湁缁撹銆?4. **闂ㄧ涓嶅彲璇诲彇**:Flutter 渚ф棤娉曟煡 `getSystemMaterialTypes()`,鍙兘瀹夸富娉ㄥ叆;璁惧(API 23 鐪熸満)鏄惁鏀寔 IMMERSIVE 闇€鍘熺敓渚ф帰娴?鍙鐢?W3/W4 鐨?Plat* 閫氶亾妯″紡)銆?5. **鏃犲崌绾у啿绐?*浣?*鏃犵郴缁熻仈鍔?*:绯荤粺璁剧疆"娌夋蹈鍏夋劅 寮?鍧囪　/寮?涓嶅彲鎰熺煡銆佷笉鍙仈鍔?鈥?浠呰瑙夎繎浼?涓庡皬绫?Miuix 娑叉€佺幓鐠冨畾浣嶄竴鑷?鍙岀鍧囧彲璺?Web 鎸?U-03 绂?銆?
---

## 6. 寤鸿(鎸?搂9,涓嶅湪鏈疆钀藉湴)

- 搂9 UI tokens(`plat_visual_tokens`)涓柊澧?**鍏夋劅妗ｄ綅 token 缁?*:`{level, blurSigma, fillOpacity, glowOpacity, shadowOpacity, specularOpacity, scatterOpacity}` + 涓夎壊鍏夋睜,榛樿 `adaptive`(=gentle,disableAnimations鈫抯mooth),鑳藉姏娉ㄥ叆璧?plat capability(涓?HUKS/picker 鍚屼竴閫氶亾妯″紡)銆?- **澶嶇敤浼樺厛**:涓绘ā绯娾啋`BackdropBlur`(缂撳瓨);楂樺厜/鍏夊湀鈫抈DualPeakHighlight`(shader 宸插氨缁?;鏁ｅ皠鈫掕瘎浼版墿 `lens_refraction.frag`(midRefraction 寰斁澶?鎴栨柊澧炶交閲?scatter shader;鍏夋睜/杈圭紭鈫掓柊澧?`GlowMaterialPainter`(绾?Canvas,鏃?shader 渚濊禆,鍙厛涓?銆?- **浜や簰鍏堜笉鍋?*(鎸夊帇鍏夊湀/鎷栨嫿寮规€?:楂樻垚鏈€佺湡鏈哄熀鍑嗙己澶?棣栫増鍙仛闈欐€佹潗璐?1鈥?),浜や簰鍒椾负浜屾湡銆?- **鎬ц兘绾㈢嚎**:璁惧鏈煡鏀寔鏃跺己鍒?`smooth`(蟽8);`exquisite` 浠呯湡鏈洪獙璇佸悗鏀惧紑;浠讳綍妗ｄ綅閮戒笉寰楀啀鐢ㄦ瘡甯у璺?BackdropFilter銆?