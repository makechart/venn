module.exports =
  pkg:
    name: 'venn', version: '0.0.1'
    # lite: 不帶 d3 的 base. 補間用 chart.anim, 可以逐格錄影 ( 見 @plotdb/chart utils/anim )
    extend: {name: "@makechart/base", path: "lite/index.html"}
    dependencies: []
    i18n:
      en:
        "only": "$1 only"
        "both": "both"
        "all": "all"
        "total": "$1 total"
      "zh-TW":
        "only": "僅 $1"
        "both": "兩者皆是"
        "all": "全部皆是"
        "total": "共 $1"
        "sets": "集合"
        "size": "數量"
        "label": "標籤"
  init: ({root, context, t, pubsub}) ->
    pubsub.fire \init, mod: mod({context, t})

svgns = "http://www.w3.org/2000/svg"
# 集合以 bitmask 表示, 超過 31 位元的位移會變號. 實務上也畫不了這麼多個
max-sets = 24

popcount = (m) ->
  c = 0
  while m
    m = m .&. (m - 1)
    c++
  c

# 0 ~ 1 的固定雜湊: 同一個點 ( id ) 每次的相位、延遲都一樣, 錄影與 snapshot 才穩定
hash = (v) ->
  x = Math.sin(v * 12.9898 + 78.233) * 43758.5453
  x - Math.floor(x)

# 兩圓 ( 半徑 r1 r2, 圓心距 d ) 的交集面積
lens = (r1, r2, d) ->
  if d >= r1 + r2 => return 0
  if d <= Math.abs(r1 - r2) => return Math.PI * Math.min(r1, r2) * Math.min(r1, r2)
  a1 = r1 * r1 * Math.acos((d * d + r1 * r1 - r2 * r2) / (2 * d * r1))
  a2 = r2 * r2 * Math.acos((d * d + r2 * r2 - r1 * r1) / (2 * d * r2))
  a3 = 0.5 * Math.sqrt((r1 + r2 - d) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2))
  a1 + a2 - a3

# 交集面積剛好是 area 時的圓心距. lens 對 d 單調遞減, 二分搜尋.
# 沒有交集時留一點縫, 不然兩圓相切看起來像是有交集
distance-for = (r1, r2, area) ->
  [lo, hi] = [Math.abs(r1 - r2), r1 + r2]
  if area <= 0 => return hi + Math.min(r1, r2) * 0.15
  if area >= lens(r1, r2, lo) => return lo
  for i from 0 til 60
    m = (lo + hi) / 2
    if lens(r1, r2, m) > area => lo = m else hi = m
  (lo + hi) / 2

split-sets = (v, sep) ->
  if !(v?) => return []
  s = "#v".trim!
  if !s => return []
  list = if sep => s.split(sep) else s.split(/\s*(?:&|∩|\||\+|,|、)\s*/)
  ret = []
  for n in list.map(-> it.trim!) => if n and !(n in ret) => ret.push n
  ret

# rows: [{names, size, label}] -> 每個 mask「剛好屬於這些集合」的值 ( exclusive ).
# inclusive 的資料 ( A = A 的總數, A&B = 交集總數 ) 用排容原理換算; 沒給的組合當成 0
build = (rows, opt = {}) ->
  names = []
  idx = {}
  vals = {}
  labels = {}
  for r in rows
    if !r.names.length or isNaN(r.size) => continue
    if r.names.some((n) -> !(idx[n]?)) and names.length + r.names.filter((n) -> !(idx[n]?)).length > max-sets => continue
    m = 0
    for n in r.names
      if !(idx[n]?)
        idx[n] = names.length
        names.push n
      m = m .|. (1 .<<. idx[n])
    vals[m] = (vals[m] or 0) + r.size
    if r.label => labels[m] = r.label
  masks = [+k for k of vals]
  exc = {}
  for m in masks
    if !opt.inclusive => exc[m] = vals[m] >? 0
    else
      v = 0
      for s in masks when (s .&. m) == m
        v += (if (popcount(s) - popcount(m)) % 2 => -1 else 1) * vals[s]
      exc[m] = v >? 0
  totals = {}
  names.map (n, i) ->
    totals[n] = masks.reduce(((a, m) -> a + if m .&. (1 .<<. i) => exc[m] else 0), 0)
  set-labels = {}
  names.map (n, i) -> if labels[1 .<<. i] => set-labels[n] = labels[1 .<<. i]
  {names, exc, labels, totals, set-labels}

# 只留下顯示中的集合 ( 圖例可以關 ). 關掉的集合從每個區域拿掉, 落到同一個區域的值相加
project = (model, visible) ->
  names = model.names.filter visible
  pos = model.names.map (n) -> names.indexOf n
  regions = {}
  for k, v of model.exc
    m = +k
    nm = 0
    for i from 0 til model.names.length
      if (m .&. (1 .<<. i)) and pos[i] >= 0 => nm = nm .|. (1 .<<. pos[i])
    if !nm => continue
    r = regions[nm] or (regions[nm] = {mask: nm, value: 0, label: ''})
    r.value += v
    # 沒被合併過的組合才用資料給的標籤. 單一集合的標籤是集合名稱, 不是區域名稱
    if popcount(nm) == popcount(m) and popcount(m) > 1 and model.labels[m] => r.label = model.labels[m]
  sets = names.map (n) -> {name: n, label: model.set-labels[n] or n, total: 0}
  regions = [v for k, v of regions]
  for r in regions
    r.names = names.filter (n, i) -> r.mask .&. (1 .<<. i)
    r.key = r.names.slice!sort!join(' & ')
    for i from 0 til names.length => if r.mask .&. (1 .<<. i) => sets[i].total += r.value
  {sets, regions, total: regions.reduce(((a, r) -> a + r.value), 0)}

pair-of = (p, i, j) ->
  b = (1 .<<. i) .|. (1 .<<. j)
  p.regions.reduce(((a, r) -> a + if (r.mask .&. b) == b => r.value else 0), 0)

# 圓的配置, 單位座標. euler: 圓面積 = 數值, 兩兩交集面積盡量對上; venn: 等大, 每種交集都畫出來
arrange = (p, mode) ->
  n = p.sets.length
  if !n => return []
  ring = (rs, ds, order) ->
    # 環的半徑 R: 每條弦 ( 相鄰兩圓的圓心距 ) 對應的圓心角加起來剛好一圈
    ang = (R) -> ds.reduce(((a, d) -> a + 2 * Math.asin(Math.min(1, d / (2 * R)))), 0)
    lo = Math.max.apply(Math, ds) / 2
    hi = ds.reduce(((a, b) -> a + b), 0)
    if ang(lo) <= 2 * Math.PI => R = lo
    else
      for i from 0 til 60
        R = (lo + hi) / 2
        if ang(R) > 2 * Math.PI => lo = R else hi = R
      R = (lo + hi) / 2
    # 繞不滿一圈 ( 某條弦特別長 ) 時等比放大圓心角, 會失真但至少閉合
    k = 2 * Math.PI / (ang(R) or 1)
    ret = []
    a = -Math.PI / 2
    for i from 0 til n
      ret[order[i]] = {x: R * Math.cos(a), y: R * Math.sin(a), r: rs[order[i]]}
      a += 2 * Math.asin(Math.min(1, ds[i] / (2 * R))) * k
    ret
  if mode == \venn
    if n == 1 => return [{x: 0, y: 0, r: 1}]
    if n == 2 => return [{x: -0.5, y: 0, r: 1}, {x: 0.5, y: 0, r: 1}]
    if n == 3
      R = 1 / Math.sqrt(3)
      return [-150, -30, 90].map (a) -> {x: R * Math.cos(a * Math.PI / 180), y: R * Math.sin(a * Math.PI / 180), r: 1}
    # 相鄰的重疊, 隔一個的不重疊 ( 2d cos(π/n) > 2r )
    d = Math.min(1.7, Math.max(1.3, 1.05 / Math.cos(Math.PI / n)))
    return ring [0 til n].map(-> 1), [0 til n].map(-> d), [0 til n]
  rs = p.sets.map (s) -> Math.sqrt((s.total >? 0) / Math.PI)
  rmax = Math.max.apply(Math, rs) or 1
  rs = rs.map -> it >? (rmax * 0.02)
  if n == 1 => return [{x: 0, y: 0, r: rs.0}]
  if n == 2 =>
    d = distance-for rs.0, rs.1, pair-of(p, 0, 1)
    return [{x: 0, y: 0, r: rs.0}, {x: d, y: 0, r: rs.1}]
  if n == 3 =>
    d01 = (distance-for rs.0, rs.1, pair-of(p, 0, 1)) >? 1e-6
    d02 = distance-for rs.0, rs.2, pair-of(p, 0, 2)
    d12 = distance-for rs.1, rs.2, pair-of(p, 1, 2)
    x = (d01 * d01 + d02 * d02 - d12 * d12) / (2 * d01)
    y = Math.sqrt((d02 * d02 - x * x) >? 0)
    return [{x: 0, y: 0, r: rs.0}, {x: d01, y: 0, r: rs.1}, {x, y, r: rs.2}]
  # 四個以上: 排成一圈, 只有相鄰的重疊. 交集大的盡量排在一起 ( greedy )
  order = [0]
  while order.length < n
    cur = order[order.length - 1]
    best = -1
    bv = -1
    for j from 0 til n
      if (j in order) or pair-of(p, cur, j) <= bv => continue
      bv = pair-of(p, cur, j)
      best = j
    order.push best
  ds = [0 til n].map (i) ->
    [a, b] = [order[i], order[(i + 1) % n]]
    distance-for rs[a], rs[b], pair-of(p, a, b)
  ring rs, ds, order

# 格點取樣: 每個點落在哪些圓裡 ( mask ), 累計各 mask 的面積, 並找離邊界最遠的點 ( 放標籤 )
analyze = (circles, res = 160) ->
  if !circles.length => return {}
  x0 = Math.min.apply(Math, circles.map -> it.x - it.r)
  x1 = Math.max.apply(Math, circles.map -> it.x + it.r)
  y0 = Math.min.apply(Math, circles.map -> it.y - it.r)
  y1 = Math.max.apply(Math, circles.map -> it.y + it.r)
  step = (Math.max(x1 - x0, y1 - y0) / res) or 1
  ret = {}
  for j from 0 til Math.ceil((y1 - y0) / step)
    y = y0 + (j + 0.5) * step
    for i from 0 til Math.ceil((x1 - x0) / step)
      x = x0 + (i + 0.5) * step
      m = 0
      dist = Infinity
      for c, k in circles
        dd = Math.sqrt((x - c.x) * (x - c.x) + (y - c.y) * (y - c.y))
        if dd < c.r => m = m .|. (1 .<<. k)
        dist = dist <? Math.abs(dd - c.r)
      if !m => continue
      a = ret[m] or (ret[m] = {count: 0, best: -1})
      a.count++
      if dist > a.best => a <<< {best: dist, x, y}
  for k, a of ret => a.area = a.count * step * step
  ret

# 一組元素在比例 s 下的範圍. 每個元素是 [a0, b0, a1, b1]: 從 s * a0 + b0 到 s * a1 + b1
# ( a 是會跟著縮放的部分, b 是固定像素, 例如文字 )
span = (items, s) ->
  if !items.length => return [0, 0]
  lo = Math.min.apply(Math, items.map -> s * it.0 + it.1)
  hi = Math.max.apply(Math, items.map -> s * it.2 + it.3)
  [lo, hi]

# 放得進 w x h 的最大比例. 範圍對 s 遞增, 二分搜尋
fit-scale = (c, w, h) ->
  if !c.ix.length => return 1
  ok = (s) ->
    [x0, x1] = span c.ix, s
    [y0, y1] = span c.iy, s
    x1 - x0 <= w and y1 - y0 <= h
  [lo, hi] = [0, 1]
  while ok(hi) and hi < 1e9 => hi = hi * 2
  for i from 0 til 50
    m = (lo + hi) / 2
    if ok(m) => lo = m else hi = m
  lo >? 1e-6

shapes =
  person: "M36 16a14 14 0 1 0 28 0a14 14 0 1 0 -28 0Z M50 34C64 34 74 42 74 56L74 70Q74 74 70 74L64 74L64 94Q64 98 60 98L40 98Q36 98 36 94L36 74L30 74Q26 74 26 70L26 56C26 42 36 34 50 34Z"
  bug: [
    "M40 22a10 10 0 1 0 20 0a10 10 0 1 0 -20 0Z"
    "M50 30C68 30 78 46 78 62C78 82 66 96 50 96C34 96 22 82 22 62C22 46 32 30 50 30Z"
    "M24 48L8 40L10 36L27 44Z M22 62L6 62L6 58L22 58Z M24 76L8 86L6 82L26 72Z"
    "M76 48L92 40L90 36L73 44Z M78 62L94 62L94 58L78 58Z M76 76L92 86L94 82L74 72Z"
    "M44 14L36 2L39 0L47 12Z M56 14L64 2L61 0L53 12Z"
  ].join(' ')

mod = ({context, t}) ->
  {chart} = context
  {format, anim: {join, interpolate}} = chart.utils
  tpl = (k, v, fb) ->
    s = t(k)
    if !(typeof(s) == \string and s.indexOf('$1') >= 0) => s = fb
    s.replace '$1', v
  word = (k, fb) ->
    s = t(k)
    if typeof(s) == \string and s and s != k => s else fb
  # 交集的顏色: 各集合顏色的平均
  blend = (cs) ->
    if !cs.length => return \#999
    c = cs.0
    for i from 1 til cs.length => c = interpolate(c, cs[i])(1 / (i + 1))
    c
  region-label = (r, n) ->
    if r.label => return r.label
    if r.names.length == 1 => return (if n == 1 => '' else tpl(\only, r.names.0, "$1 only"))
    if r.names.length == n => return (if n == 2 => word(\both, "both") else word(\all, "all"))
    r.names.join ' & '

  sample: ->
    raw: [
      {sets: "Trial users", size: 580}
      {sets: "Paying users", size: 463}
      {sets: "Trial users & Paying users", size: 168}
    ]
    binding:
      sets: {key: \sets}
      size: {key: \size}
  config: {
    legend: {} <<< chart.utils.config.preset.legend
    tip: JSON.parse(JSON.stringify chart.utils.config.preset.tip)
  } <<< chart.utils.config.preset.default <<<
    layout: type: \choice, values: <[euler venn]>, default: \euler, desc: {en: "euler: circle areas follow the values and overlaps follow the shared amounts; venn: equal circles that show every overlap", "zh-TW": "euler：圓的面積依數值，重疊的大小依交集的數量；venn：大小相同的圓，畫出所有交集"}
    value: type: \choice, values: <[inclusive exclusive]>, default: \inclusive, desc: {en: "what a row's value means. inclusive: A is everyone in A and A & B everyone in both; exclusive: A is only those in A alone", "zh-TW": "每列數值的意義。inclusive：A 是 A 的全部、A & B 是交集的全部；exclusive：A 只算只屬於 A 的"}
    separator: type: \text, default: '', desc: {en: "character between set names in a combination, e.g. A&B; empty accepts & ∩ | + , and 、", "zh-TW": "組合裡集合名稱之間的分隔字元，例如 A&B；空白表示 & ∩ | + , 、 都可以"}
    style: type: \choice, values: <[area dot]>, default: \area, desc: {en: "area: filled circles; dot: circles made of small dots, each dot a fixed amount", "zh-TW": "area：填色的圓；dot：由小點組成的圓，每點代表固定的數量"}
    circle:
      opacity: type: \number, default: 0.3, min: 0, max: 1, step: 0.01, desc: {en: "fill opacity of the circles; overlaps get darker as fills stack", "zh-TW": "圓的填色透明度；重疊處因疊色而變深"}
      stroke: type: \number, default: 2.5, min: 0, max: 20, step: 0.5, desc: {en: "outline width of the circles ( px ); 0 for none", "zh-TW": "圓的外框粗細 ( px )；0 表示不畫"}
    label:
      set:
        enabled: type: \boolean, default: true, desc: {en: "show each set's name next to its circle", "zh-TW": "在圓旁邊標出集合名稱"}
        total: type: \boolean, default: true, desc: {en: "show each set's total under its name", "zh-TW": "在集合名稱下方標出該集合的總數"}
      value:
        enabled: type: \boolean, default: true, desc: {en: "show the amount in each region", "zh-TW": "在每個區域標出數量"}
        format: type: \format, default: ',', desc: {en: "number format of the amounts, e.g. , or .3s ( d3-format )", "zh-TW": "數量的格式，例如 , 或 .3s ( d3-format )"}
        percent: type: \boolean, default: false, desc: {en: "also show each region's share of everyone", "zh-TW": "同時標出每個區域佔全體的比例"}
      region:
        enabled: type: \boolean, default: true, desc: {en: "name each region under its amount, e.g. A only or both", "zh-TW": "在數量下方標出區域名稱，例如「僅 A」或「兩者皆是」"}
    dot:
      shape: type: \choice, values: <[circle square person bug]>, default: \circle, desc: {en: "shape of each dot", "zh-TW": "每個點的形狀"}
      unit: type: \number, default: 0, min: 0, max: 1000000000, step: 0.01, desc: {en: "amount each dot stands for; 0 picks a round number automatically", "zh-TW": "每個點代表的數量；0 表示自動挑一個整齊的數"}
      count: type: \number, default: 300, min: 10, max: 3000, step: 10, desc: {en: "about how many dots to draw when the unit is automatic", "zh-TW": "自動決定單位時，大約要畫幾個點"}
      size: type: \number, default: 0.75, min: 0.1, max: 1.5, step: 0.05, desc: {en: "dot size relative to the space between dots", "zh-TW": "點的大小，相對於點與點的間距"}
      motion: type: \choice, values: <[none jiggle wander]>, default: \jiggle, desc: {en: "idle movement of the dots: none, a small jiggle, or wandering around", "zh-TW": "點平常的動態：不動、輕微抖動、或四處走動"}
      speed: type: \number, default: 1, min: 0.1, max: 5, step: 0.1, desc: {en: "speed of the idle movement", "zh-TW": "平常動態的速度"}
      outline: type: \boolean, default: true, desc: {en: "keep the circle outlines in dot style", "zh-TW": "dot 樣式下保留圓的外框"}
  tabinfo: chart.utils.config.tabinfo({legend: \legend, tip: \tip}) <<<
    circle: desc: {en: "fill and outline of the circles", "zh-TW": "圓的填色與外框"}
    label: desc: {en: "text on the chart: set names, amounts and region names", "zh-TW": "圖上的文字：集合名稱、數量與區域名稱"}
    "label/set": desc: {en: "set names and totals next to the circles", "zh-TW": "圓旁邊的集合名稱與總數"}
    "label/value": desc: {en: "the amount in each region", "zh-TW": "每個區域的數量"}
    "label/region": desc: {en: "region names such as A only or both", "zh-TW": "區域名稱，例如「僅 A」、「兩者皆是」"}
    dot: desc: {en: "dot style: what each dot looks like, how much it stands for and how it moves", "zh-TW": "dot 樣式：點的樣子、代表的數量與動態"}
  dimension:
    # 這一列屬於哪些集合, 例如 A、A&B. 一列可以是一個組合的數量, 也可以是一筆原始資料 ( 不綁 size 時每列算 1 )
    sets: {type: \NC, name: "sets", priority: 1}
    size: {type: \R, name: "size", priority: 2}
    # 單一集合那一列: 集合的顯示名稱; 組合那一列: 區域的名稱
    label: {type: \NC, name: "label", passive: true}
  init: ->
    @tint = tint = new chart.utils.tint!
    @g = view: @layout.get-group(\view), legend: @layout.get-group(\legend)
    for k in <[fill bubble outline dot rlabel slabel]>
      n = document.createElementNS svgns, \g
      n.setAttribute \class, k
      @g[k] = @g.view.appendChild n
    @legend = new chart.utils.legend do
      layout: @layout
      name: \legend
      root: @root
      shape: (d) -> @setAttribute \fill, tint.get(d.key)
    @legend.on \select, ~> @bind!; @resize!; @render!
    @_canvas = document.createElement(\canvas).getContext \2d
    @_dots = new Map!
    @_dot-id = 0
    @tip = new chart.utils.tip {
      root: @root
      accessor: ({evt}) ~>
        if !(@geo and evt.clientX?) => return null
        rect = @layout.get-node(\view).getBoundingClientRect!
        r = @mod.hit.call @, evt.clientX - rect.x, evt.clientY - rect.y
        if !r => return null
        fmt = format.from(@cfg.tip.format or ',')
        total = @geo.total or 1
        return {
          name: r.text or r.names.join(' & ')
          group: if r.text and r.names.length > 1 => r.names.join(' ∩ ') else ''
          value: fmt(r.value)
          value-alt: "(#{(r.value * 100 / total).toFixed(1)}%)"
        }
      range: ~> @layout.get-node \view .getBoundingClientRect!
    }

  destroy: ->
    @stop!
    if @tip => @tip.destroy!

  filter-dims: -> []
  interactions: -> {}

  # 檢視區座標 -> 指到的區域
  hit: (x, y) ->
    if !@geo => return null
    for b in @geo.bubbles => if (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) <= b.r * b.r => return b.region
    m = 0
    for c, i in @geo.circles => if (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= c.r * c.r => m = m .|. (1 .<<. i)
    if !m => return null
    @geo.by-mask[m] or null

  parse: ->
    # 配色依「第幾個遇到的 key」分配, 先重置再依序取一次, 換資料或換格時顏色才不會跑掉
    @tint.reset!
    if @cfg.palette => @tint.set @cfg.palette
    sep = @cfg.separator or ''
    opt = {inclusive: @cfg.value != \exclusive}
    has-size = !!@binding.size
    rows-of = (data) -> data.map (d) ->
      names: split-sets d.sets, sep
      size: if has-size => +d.size else 1
      label: if d.label? => "#{d.label}".trim! else ''
    @_model = build rows-of(@data), opt
    # 動畫 ( dataframe ) 時每一格都要算: 圖例、配色與大小比例要跨格一致, 圓才不會每格重新縮放
    @_models = if @frame.active! and @_frames => @_frames.list.map (f) ~> build rows-of(@_parse-rows f.raw), opt
    else [@_model]
    @_names = []
    @_set-label = {}
    for m in @_models
      for n in m.names
        if !(n in @_names) => @_names.push n
        if m.set-labels[n] => @_set-label[n] = m.set-labels[n]
    @_names.map (n) ~> @tint.get n
    # 點的單位依全部集合 ( 不管圖例開關 ) 的最大總量: 關掉一個集合時點才守恆, 只是換區域
    @_all-total = Math.max.apply(Math, @_models.map (m) -> [v for k, v of m.exc].reduce(((a, b) -> a + b), 0)) or 0
    @_fcache = null

  resize: ->
    @root.querySelector('.pdl-layout').classList.toggle \legend-bottom, @cfg.legend.position == \bottom
    @legend.config @cfg.legend
    @legend.data @_names.map (n) ~> {key: n, text: @_set-label[n] or n, value: @_model.totals[n] or 0}
    @layout.update false
    box = @layout.get-box \view
    [W, H] = [box.width, box.height]
    # 不在畫面上 ( 被移除、隱藏 ) 時是 0: 不排版, 點的格距會變 0, 填點的迴圈跑不完
    if !(W > 0 and H > 0) => return
    style = window.getComputedStyle @root
    fs = parseFloat(style.fontSize) or 14
    family = style.fontFamily or 'sans-serif'
    measure = (txt, size, bold) ~>
      @_canvas.font = "#{if bold => 'bold ' else ''}#{size}px #family"
      @_canvas.measureText(txt or '').width
    lab = @cfg.label or {}
    fmt = format.from((lab.value or {}).format or ',')
    show-set = !!(lab.set or {}).enabled
    show-total = show-set and !!(lab.set or {}).total
    ts = fs * 1.2
    us = fs * 0.9
    gap = fs * 1.4
    mode = @cfg.layout or \euler
    lg = @legend
    visible = (n) -> !lg.enabled! or lg.is-selected(n)

    # 單位座標下的版面, 以及放進檢視區時要算進去的範圍 ( ix / iy, 見 span )
    compose = (model) ~>
      p = project model, visible
      circles = arrange p, mode
      n = circles.length
      geo = analyze circles
      by-mask = {}
      for r in p.regions
        g = geo[r.mask]
        r.geo = if g and g.count >= 3 => g else null
        by-mask[r.mask] = r
      # 圖上有, 資料裡沒有的區域 ( 值是 0 )
      for k, g of geo
        if by-mask[k] or g.count < 3 => continue
        names = p.sets.map(-> it.name).filter (nm, i) -> +k .&. (1 .<<. i)
        r = {mask: +k, value: 0, label: '', names, key: names.slice!sort!join(' & '), geo: g, empty: true}
        p.regions.push r
        by-mask[k] = r
      p.regions.map (r) -> r.text = region-label(r, n)
      # 圖上畫不出來的組合 ( 四個以上不相鄰的、三個以上的交集 ... ) 退化成獨立的泡泡
      vmax = Math.max.apply(Math, p.regions.map(-> it.value) ++ [0]) or 1
      rmean = (circles.reduce(((a, c) -> a + c.r), 0) / (n or 1)) or 1
      bubbles = p.regions
        .filter (r) -> !r.geo and r.value > 0
        .map (r) -> {region: r, r: (if mode == \venn => 0.55 * Math.sqrt(r.value / vmax) >? 0.18 else Math.sqrt(r.value / Math.PI))}
        .sort (a, b) -> b.r - a.r
      cx = circles.reduce(((a, c) -> a + c.x), 0) / (n or 1)
      cy = circles.reduce(((a, c) -> a + c.y), 0) / (n or 1)
      pad = rmean * 0.12
      # 泡泡底下的名稱也不能壓到圓. 文字是固定像素, 先用只有圓時的比例估算它在單位座標裡多大
      s0 = fit-scale {ix: circles.map((c) -> [c.x - c.r, 0, c.x + c.r, 0]), iy: circles.map((c) -> [c.y - c.r, 0, c.y + c.r, 0])}, W, H
      # 圓心到矩形的距離
      rect-dist = (c, x0, y0, x1, y1) ->
        dx = Math.max(x0 - c.x, 0, c.x - x1)
        dy = Math.max(y0 - c.y, 0, c.y - y1)
        Math.sqrt(dx * dx + dy * dy)
      placed = []
      for b in bubbles
        lw = measure(b.region.text, fs * 0.85) / 2 / s0
        lh = fs * 1.4 / s0
        for i from 0 til 6000
          a = i * 0.35
          d = i * rmean * 0.004
          [x, y] = [cx + d * Math.cos(a), cy + d * Math.sin(a)]
          free = (c) ->
            Math.sqrt((x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)) >= c.r + b.r + pad and
            rect-dist(c, x - lw, y + b.r, x + lw, y + b.r + lh) >= c.r + pad * 0.5
          if circles.every(free) and placed.every(free) => break
        b <<< {x, y}
        placed.push b
      # 集合名稱往外放 ( 離中心的方向, 偏上 ). 方向與比例無關, 所以可以先算好
      ix = []
      iy = []
      sets = circles.map (c, i) ->
        s = p.sets[i]
        [vx, vy] = [c.x - cx, c.y - cy]
        len = Math.sqrt(vx * vx + vy * vy)
        [ox, oy] = if len > 1e-9 => [vx / len, vy / len] else [0, 0]
        [dx, dy] = if n <= 2 => [ox * 0.55, oy - 1] else (if len > 1e-9 => [ox, oy - 0.35] else [0, -1])
        dl = Math.sqrt(dx * dx + dy * dy) or 1
        [dx, dy] = [dx / dl, dy / dl]
        anchor = if dx > 0.6 => \start else if dx < -0.6 => \end else \middle
        tw = Math.max(measure(s.label, ts, true), (if show-total => measure(tpl(\total, fmt(s.total), "$1 total"), us) else 0))
        th = ts + (if show-total => us * 1.3 else 0)
        pos = if dy < -0.3 => \above else if dy > 0.3 => \below else \side
        bx = if anchor == \start => [0, tw] else if anchor == \end => [-tw, 0] else [-tw / 2, tw / 2]
        yb = if pos == \above => [-th, 0] else if pos == \below => [0, th] else [-ts, th - ts]
        ix.push [c.x - c.r, 0, c.x + c.r, 0]
        iy.push [c.y - c.r, 0, c.y + c.r, 0]
        if show-set and s.label =>
          [ex, ey] = [c.x + dx * c.r, c.y + dy * c.r]
          ix.push [ex, dx * gap + bx.0, ex, dx * gap + bx.1]
          iy.push [ey, dy * gap + yb.0, ey, dy * gap + yb.1]
        {name: s.name, label: s.label, total: s.total, x: c.x, y: c.y, r: c.r, dx, dy, anchor, pos}
      for b in bubbles
        ix.push [b.x - b.r, 0, b.x + b.r, 0]
        w = measure(b.region.text, fs * 0.85) / 2
        ix.push [b.x, -w, b.x, w]
        iy.push [b.y - b.r, 0, b.y + b.r, fs * 2.4]
      {p, sets, bubbles, by-mask, ix, iy}

    cur = compose @_model
    # 動畫時取所有格裡最小的比例, 圓的大小才能跨格比較
    sig = JSON.stringify [@_names.filter(visible), mode, @cfg.value, fs, W, H, lab]
    if !(@_fcache and @_fcache.sig == sig) =>
      cs = if @_models.length > 1 => @_models.map(compose) else [cur]
      @_fcache = {sig, scale: Math.min.apply(Math, cs.map (c) -> fit-scale(c, W, H))}
    s = @_fcache.scale
    [x0, x1] = span cur.ix, s
    [y0, y1] = span cur.iy, s
    ox = (W - (x1 - x0)) / 2 - x0
    oy = (H - (y1 - y0)) / 2 - y0
    X = (v) -> ox + s * v
    Y = (v) -> oy + s * v
    color = (names) ~> blend names.map (n) ~> @tint.get n

    circles = cur.sets.map (c) ~>
      [ex, ey] = [X(c.x + c.dx * c.r), Y(c.y + c.dy * c.r)]
      c <<< {x: X(c.x), y: Y(c.y), r: s * c.r, color: @tint.get(c.name), ex, ey, lx: ex + c.dx * gap, ly: ey + c.dy * gap}
    bubbles = cur.bubbles.map (b) -> b <<< {x: X(b.x), y: Y(b.y), r: s * b.r}
    vs = fs * 1.9
    ls = fs * 0.95
    total = cur.p.total or 1
    labels = []
    for r in cur.p.regions
      r.color = color r.names
      b = bubbles.find -> it.region == r
      if r.geo => r <<< {x: X(r.geo.x), y: Y(r.geo.y), dist: s * r.geo.best, area: s * s * r.geo.area}
      else if b => r <<< {x: b.x, y: b.y, dist: b.r, area: Math.PI * b.r * b.r, bubble: b}
      else continue
      if r.value <= 0 and !(mode == \venn and r.geo) => continue
      vt = fmt(r.value) + (if (lab.value or {}).percent => " (#{Math.round(r.value * 100 / total)}%)" else '')
      # 字放不下就縮, 縮到太小就不放
      k = Math.min(1, (r.dist * 2) / ((measure(vt, vs, true)) or 1), r.dist / (vs * 0.55))
      size = vs * k
      show-v = !!(lab.value or {}).enabled and size >= fs * 0.75
      show-l = !!(lab.region or {}).enabled and !!r.text and
        (if r.bubble => true else (show-v and r.dist >= (size * 0.6 + ls * 1.2) and measure(r.text, ls) <= r.dist * 2.2))
      if r.bubble and !show-v => vt = ''
      labels.push {
        key: r.key, x: r.x, y: r.y, value: r.value, vt, vsize: size, show-v, lt: r.text, lsize: ls, show-l
        bubble: !!r.bubble, r: (r.dist or 0), percent: !!(lab.value or {}).percent, total
      }
    @geo = {circles, bubbles, labels, total: cur.p.total, regions: cur.p.regions, by-mask: cur.by-mask, fs, ts, us, show-set, show-total, fmt}

    if @cfg.style == \dot => @mod.dot-layout.call @, @_all-total
    else @dots = []

  # 點的版面: 先決定每點代表多少 ( unit ), 再用六角格點把每個區域填滿, 最後把點分配到格點上
  dot-layout: (all-total) ->
    cfg = @cfg.dot or {}
    unit = +cfg.unit
    if !(unit > 0) =>
      raw = (all-total or 1) / (cfg.count or 300)
      e = Math.pow(10, Math.floor(Math.log10(raw)))
      unit = [1 2 2.5 5 10].map(-> it * e).find(-> it >= raw) or raw
    # 點太多畫不動
    unit = unit >? (all-total / 5000)
    {circles, bubbles} = @geo
    regs = @geo.regions.filter (r) -> r.value > 0 and (r.geo or r.bubble)
    regs.map (r) -> r.k = Math.round(r.value / unit)
    regs = regs.filter (r) -> r.k > 0
    if !regs.length =>
      @dots = []
      return @_dots = new Map!
    by-mask = {}
    regs.map (r) -> if !r.bubble => by-mask[r.mask] = r
    # 每點分到的面積 ( 六角格點一點佔 0.866 s² ), 邊緣放不滿, 打個折
    step = Math.min.apply(Math, regs.map (r) -> Math.sqrt(r.area * 0.8 / (r.k * 0.866)))
    box = @layout.get-box \view
    step = step <? (Math.min(box.width, box.height) / 4)
    # 格距要是正數, 不然下面的迴圈跑不完
    if !(step > 0 and isFinite(step)) =>
      @dots = []
      return @_dots = new Map!
    all = circles.map((c) -> [c.x, c.y, c.r]) ++ bubbles.map((b) -> [b.x, b.y, b.r])
    x0 = Math.min.apply(Math, all.map -> it.0 - it.2)
    x1 = Math.max.apply(Math, all.map -> it.0 + it.2)
    y0 = Math.min.apply(Math, all.map -> it.1 - it.2)
    y1 = Math.max.apply(Math, all.map -> it.1 + it.2)
    for tries from 0 til 16
      pts = {}
      margin = step * 0.5
      rh = step * 0.866
      for j from 0 to Math.ceil((y1 - y0) / rh)
        y = y0 + j * rh
        for i from 0 to Math.ceil((x1 - x0) / step)
          x = x0 + i * step + (if j % 2 => step / 2 else 0)
          r = null
          for b in bubbles => if Math.sqrt((x - b.x) * (x - b.x) + (y - b.y) * (y - b.y)) <= b.r - margin => r = b.region
          if !r
            m = 0
            dist = Infinity
            for c, k in circles
              dd = Math.sqrt((x - c.x) * (x - c.x) + (y - c.y) * (y - c.y))
              if dd < c.r => m = m .|. (1 .<<. k)
              dist = dist <? Math.abs(dd - c.r)
            if m and dist >= margin => r = by-mask[m]
          if r => (pts[r.key] or (pts[r.key] = [])).push [x, y]
      if regs.every((r) -> (pts[r.key] or []).length >= r.k) => break
      step = step * 0.93
    # 由區域中心往外排: 少了的點從外圈拿走, 每格之間位置大致不變
    for r in regs
      list = pts[r.key] or []
      list.sort (a, b) -> ((a.0 - r.x) ** 2 + (a.1 - r.y) ** 2) - ((b.0 - r.x) ** 2 + (b.1 - r.y) ** 2)
      r.pts = list
      r.k = r.k <? list.length
    @_dot-step = step
    @_dot-unit = unit
    @dots = @mod.dot-assign.call @, regs

  # 把點分配到區域. 點有身分 ( id ): 區域變小時多出來的點會走到變大的區域, 優先選共同集合多的 -
  # 例如「僅 A」少了、「A & B」多了, 就是同一批點從 A 走進交集. 不夠的才新生, 多的才消失
  dot-assign: (regs) ->
    by-key = {}
    @_dots.forEach (d) -> (by-key[d.key] or (by-key[d.key] = [])).push d
    pool = []
    keys = regs.map (.key)
    for k, list of by-key => if !(k in keys) => pool = pool.concat list
    for r in regs
      list = (by-key[r.key] or []).sort (a, b) -> a.slot - b.slot
      r._keep = list.slice 0, r.k
      pool = pool.concat list.slice(r.k)
      r._in = []
    sim = (a, b) ->
      c = a.filter(-> it in b).length
      c / ((a.length + b.length - c) or 1)
    for r in regs.slice!sort((a, b) -> (b.k - b._keep.length) - (a.k - a._keep.length))
      need = r.k - r._keep.length
      if need <= 0 or !pool.length => continue
      pool.map (d) -> d._sim = sim(d.names, r.names)
      pool.sort (a, b) -> (b._sim - a._sim) or (a.id - b.id)
      r._in = pool.splice 0, need
    ret = []
    for r in regs
      for d, i in r._keep => d.slot = i
      free = [r._keep.length til r.k]
      # 走進來的點挑離自己最近的空位
      for d in r._in
        if !free.length => break
        bi = 0
        if free.length * r._in.length < 200000
          bd = Infinity
          for f, i in free
            [px, py] = r.pts[f]
            dd = (px - d.x) * (px - d.x) + (py - d.y) * (py - d.y)
            if dd < bd => [bd, bi] = [dd, i]
        d.slot = free.splice(bi, 1).0
        d.moved = true
      fresh = free.map (f) ~> {id: @_dot-id++, slot: f, fresh: true}
      for d in r._keep ++ r._in ++ fresh
        if !(d.slot?) => continue
        [x, y] = r.pts[d.slot]
        d <<< {key: r.key, names: r.names, x, y, color: r.color}
        ret.push d
    @_dots = new Map(ret.map (d) -> [d.id, d])
    ret

  render: ->
    {geo, cfg} = @
    if !geo => return
    tween = (n, attrs, opt) ~> @anim.tween n, attrs, opt
    dot = cfg.style == \dot
    fo = (cfg.circle or {}).opacity ? 0.3
    sw = (cfg.circle or {}).stroke ? 2.5
    halo = if dot => (if cfg.background and cfg.background != \transparent => cfg.background else \#fff) else null
    txt = cfg.color or \currentColor
    mk = (p, tag, cls) ->
      n = document.createElementNS svgns, tag
      if cls => n.setAttribute \class, cls
      p.appendChild n
    text-attr = (n, size, bold) ->
      n.setAttribute \font-size, size
      n.setAttribute \font-weight, (if bold => \bold else \normal)
      if halo =>
        n.setAttribute \stroke, halo
        n.setAttribute \stroke-width, 3
        n.setAttribute \stroke-opacity, 0.85
        n.setAttribute \stroke-linejoin, \round
        n.setAttribute \paint-order, \stroke
      else n.removeAttribute \stroke

    # 圓: 填色與外框分兩層, 外框才不會被另一個圓的填色蓋住
    for [root, outline] in [[@g.fill, false], [@g.outline, true]]
      cj = join root: root, tag: \circle, cls: \set, data: geo.circles, key: (.name)
      cj.exit.map (n) -> tween n, {r: 0}, {remove: true}
      cj.enter.map (n) ->
        d = n.__data__
        n.setAttribute \cx, d.x
        n.setAttribute \cy, d.y
        n.setAttribute \r, 0
        n.setAttribute \fill, (if outline => \none else d.color)
        if outline => n.setAttribute \stroke, d.color
      cj.nodes.map (n) ->
        d = n.__data__
        if outline =>
          tween n, {cx: d.x, cy: d.y, r: d.r, stroke: d.color, "stroke-width": (if dot and !cfg.dot.outline => 0 else sw), "stroke-opacity": (if dot => 0.6 else 1)}
        else
          tween n, {cx: d.x, cy: d.y, r: d.r, fill: d.color, "fill-opacity": (if dot => fo * 0.25 else fo)}

    # 畫不出來的組合: 虛線框的泡泡
    bj = join root: @g.bubble, tag: \circle, cls: \bubble, data: geo.bubbles, key: (.region.key)
    bj.exit.map (n) -> tween n, {r: 0}, {remove: true}
    bj.enter.map (n) ->
      d = n.__data__
      n.setAttribute \cx, d.x
      n.setAttribute \cy, d.y
      n.setAttribute \r, 0
      n.setAttribute \stroke-dasharray, "4 3"
    bj.nodes.map (n) ->
      d = n.__data__
      c = d.region.color
      tween n, {cx: d.x, cy: d.y, r: d.r, fill: c, stroke: c, "fill-opacity": (if dot => fo * 0.25 else fo * 1.4 <? 1), "stroke-width": sw * 0.6 >? 1}

    # 點
    shape = cfg.dot.shape or \circle
    dr = (@_dot-step or 0) * (cfg.dot.size or 0.75) / 2
    dj = join root: @g.dot, tag: \g, cls: \dot, data: (if dot => @dots else []), key: (.id)
    dj.exit.map (n) -> tween n, {opacity: 0}, {duration: 250, remove: true}
    dj.enter.map (n) ->
      d = n.__data__
      n.setAttribute \transform, "translate(#{d.x},#{d.y})"
      n.setAttribute \opacity, 0
      mk n, \g, \wig
    sig = "#shape:#dr"
    dj.nodes.map (n) ->
      d = n.__data__
      w = n.firstChild
      if w._sig != sig =>
        w._sig = sig
        w.textContent = ''
        if shape == \circle =>
          s = mk w, \circle
          s.setAttribute \r, dr
        else if shape == \square =>
          s = mk w, \rect
          s.setAttribute \x, -dr * 0.9
          s.setAttribute \y, -dr * 0.9
          s.setAttribute \width, dr * 1.8
          s.setAttribute \height, dr * 1.8
        else
          s = mk w, \path
          s.setAttribute \d, shapes[shape] or shapes.person
          s.setAttribute \transform, "scale(#{dr * 2.3 / 100}) translate(-50,-50)"
        s.setAttribute \fill, d.color
      tween w.firstChild, {fill: d.color}
      opt = if d.moved => {duration: 800, delay: hash(d.id) * 450} else {}
      tween n, {transform: "translate(#{d.x},#{d.y})", opacity: 1}, opt
      d.moved = d.fresh = false
    @_wigs = Array.from(@g.dot.querySelectorAll ':scope > g.dot > g.wig')
    if dot and cfg.dot.motion != \none and @_wigs.length => @start!
    else
      @stop!
      @_wigs.map -> it.removeAttribute \transform

    # 區域的數字與名稱. 數字換資料時用跑的
    fmt = geo.fmt
    lj = join root: @g.rlabel, tag: \g, cls: \rl, data: geo.labels, key: (.key)
    lj.exit.map (n) -> tween n, {opacity: 0}, {duration: 200, remove: true}
    lj.enter.map (n) ->
      d = n.__data__
      n.setAttribute \transform, "translate(#{d.x},#{d.y})"
      n.setAttribute \opacity, 0
      for c in <[v l]>
        e = mk n, \text, "venn-text #c"
        e.setAttribute \text-anchor, \middle
        e.setAttribute \dominant-baseline, \central
    lj.nodes.map (n) ->
      d = n.__data__
      [v, l] = [n.childNodes.0, n.childNodes.1]
      text-attr v, d.vsize, true
      text-attr l, d.lsize, false
      v.setAttribute \fill, txt
      l.setAttribute \fill, txt
      l.setAttribute \fill-opacity, 0.75
      v.style.display = if d.show-v and d.vt => '' else \none
      l.style.display = if d.show-l => '' else \none
      l.textContent = d.lt
      if d.bubble =>
        # 泡泡: 數字在裡面, 名稱在下面
        v.setAttribute \y, 0
        l.setAttribute \y, d.r + d.lsize * 0.9
        if !d.vt => l.textContent = "#{d.lt} #{fmt(d.value)}"
      else
        v.setAttribute \y, (if d.show-l => -d.lsize * 0.6 else 0)
        l.setAttribute \y, d.vsize * 0.5 + d.lsize * 0.45
      from = if n._v? => n._v else d.value
      to = d.value
      n._v = to
      pct = (x) -> if d.percent => " (#{Math.round(x * 100 / d.total)}%)" else ''
      v.textContent = d.vt
      if from != to and d.vt =>
        int = from % 1 == 0 and to % 1 == 0
        tween v, {"data-v": (k) ->
          x = from + (to - from) * k
          v.textContent = fmt(if int => Math.round(x) else x) + pct(x)
          x
        }
      tween n, {transform: "translate(#{d.x},#{d.y})", opacity: 1}

    # 集合名稱 + 總數, 用虛線拉到圓上
    sj = join root: @g.slabel, tag: \g, cls: \sl, data: (if geo.show-set => geo.circles.filter(-> it.label) else []), key: (.name)
    sj.exit.map (n) -> tween n, {opacity: 0}, {duration: 200, remove: true}
    sj.enter.map (n) ->
      n.setAttribute \opacity, 0
      ln = mk n, \line, \leader
      ln.setAttribute \stroke-dasharray, "3 3"
      ln.setAttribute \stroke-width, 1.5
      for c in <[title total]> => mk n, \text, "venn-text #c"
    sj.nodes.map (n) ->
      d = n.__data__
      [ln, a, b] = [n.childNodes.0, n.childNodes.1, n.childNodes.2]
      ts = geo.ts
      us = geo.us
      [ay, yb] = if d.pos == \above =>
        if geo.show-total => [-us * 1.3 - ts * 0.25, -us * 0.25] else [-ts * 0.25, 0]
      else if d.pos == \below => [ts * 0.85, ts * 0.85 + us * 1.3]
      else [-ts * 0.15, us * 1.1]
      for [e, y] in [[a, ay], [b, yb]]
        e.setAttribute \text-anchor, d.anchor
        e.setAttribute \y, y
      text-attr a, ts, true
      text-attr b, us, false
      # 集合顏色淺的 ( 例如黃色 ) 當文字太淡, 往黑色調一點
      a.setAttribute \fill, interpolate(d.color, \#000)(0.25)
      b.setAttribute \fill, txt
      b.setAttribute \fill-opacity, 0.55
      a.textContent = d.label
      b.textContent = tpl(\total, geo.fmt(d.total), "$1 total")
      b.style.display = if geo.show-total => '' else \none
      ln.setAttribute \stroke, txt
      ln.setAttribute \stroke-opacity, 0.3
      [ux, uy] = [d.dx, d.dy]
      tween ln, {x1: d.ex - d.lx + ux * 2, y1: d.ey - d.ly + uy * 2, x2: -ux * 4, y2: -uy * 4}
      tween n, {transform: "translate(#{d.lx},#{d.ly})", opacity: 1}

    @legend.render!

  # 點的閒置動態. 位移只是時間的函數 ( 每點相位不同 ), 不累積狀態, 逐格錄影也一樣
  tick: (t) ->
    if !(@_wigs and @_wigs.length) or @cfg.style != \dot => return
    motion = @cfg.dot.motion
    if motion == \none => return
    wander = motion == \wander
    amp = (@_dot-step or 0) * (if wander => 0.45 else 0.1)
    sp = (@cfg.dot.speed or 1) * 0.001 * (if wander => 0.8 else 4)
    rot = wander and @cfg.dot.shape == \bug
    tt = t * sp
    for w in @_wigs
      d = w.parentNode.__data__
      if !d => continue
      h = d._h or (d._h = [0 1 2 3 4 5 6 7].map (i) -> hash(d.id * 8 + i))
      [f1, f2, f3, f4] = [0.6 + h.0 * 0.8, 1.2 + h.1, 0.6 + h.2 * 0.8, 1.2 + h.3]
      [p1, p2, p3, p4] = [h.4 * 6.283, h.5 * 6.283, h.6 * 6.283, h.7 * 6.283]
      dx = amp * (0.7 * Math.sin(tt * f1 + p1) + 0.3 * Math.sin(tt * f2 + p2))
      dy = amp * (0.7 * Math.cos(tt * f3 + p3) + 0.3 * Math.sin(tt * f4 + p4))
      tr = "translate(#dx,#dy)"
      if rot =>
        vx = 0.7 * f1 * Math.cos(tt * f1 + p1) + 0.3 * f2 * Math.cos(tt * f2 + p2)
        vy = -0.7 * f3 * Math.sin(tt * f3 + p3) + 0.3 * f4 * Math.cos(tt * f4 + p4)
        tr += " rotate(#{Math.atan2(vy, vx) * 180 / Math.PI + 90})"
      w.setAttribute \transform, tr
