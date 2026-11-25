# venn 的 test case ( 用 @makechart/viewer 的 mctest 跑, 見 README / `npx mctest -h` )

rows = (list) -> list.map ([sets, size]) -> {sets, size}
bind = sets: {key: \sets}, size: {key: \size}

data =
  two: raw: rows([["Trial users", 580], ["Paying users", 463], ["Trial users & Paying users", 168]]), binding: bind
  one: raw: rows([["Everyone", 300]]), binding: bind
  three: raw: rows([
    ["Coffee", 100], ["Tea", 80], ["Juice", 60]
    ["Coffee&Tea", 30], ["Coffee&Juice", 20], ["Tea&Juice", 15], ["Coffee&Tea&Juice", 5]
  ]), binding: bind
  # exclusive: 每列是「剛好只屬於這些集合」
  exclusive: raw: rows([["A", 40], ["B", 30], ["C", 20], ["A,B", 12], ["B,C", 6]]), binding: bind
  # 互不相交 / 完全包含
  disjoint: raw: rows([["A", 50], ["B", 30]]), binding: bind
  subset: raw: rows([["All", 100], ["Some", 30], ["All&Some", 30]]), binding: bind
  # 五個: 排成一圈, 不相鄰的 ( A&C ) 與三個的交集退化成泡泡
  ring: raw: rows([
    ["A", 50], ["B", 50], ["C", 50], ["D", 50], ["E", 50]
    ["A&B", 10], ["B&C", 10], ["C&D", 10], ["D&E", 10], ["E&A", 10], ["A&C", 8], ["A&B&C", 3]
  ]), binding: bind
  # 原始資料: 不綁 size, 每列算 1
  records: do ->
    r = mctest.random 5
    raw: [0 til 120].map (i) ->
      v = r!
      {id: i, sets: if v < 0.4 => "X" else if v < 0.7 => "Y" else "X&Y"}
    binding: sets: {key: \sets}
  labeled:
    raw: [
      {sets: "Trial", size: 580, label: "Trial users"}
      {sets: "Paying", size: 463, label: "Paying users"}
      {sets: "Trial&Paying", size: 168, label: "converted"}
    ]
    binding: bind <<< label: {key: \label}
  empty: raw: [], binding: bind

# 動畫: 三格, 點從「僅 Trial」走進交集
frames = do ->
  f = (id, a, b, ab) -> {id, raw: rows([["Trial", a], ["Paying", b], ["Trial&Paying", ab]])}
  {frames: [f(2020, 500, 200, 60), f(2021, 520, 300, 160), f(2022, 540, 420, 300)]}
data.frames = raw: frames, binding: bind

cases = []
for k in <[two one three exclusive disjoint subset ring records labeled empty]>
  cases.push {name: "data:#k", data: k, config: (if k == \exclusive => {value: \exclusive} else {})}

cases ++= [
  * name: "layout:venn,three", data: \three, config: {layout: \venn}
  * name: "layout:venn,ring", data: \ring, config: {layout: \venn}
  * name: "label:off", data: \two, config: {label: {set: {enabled: false}, value: {enabled: false}, region: {enabled: false}}}
  * name: "label:percent", data: \three, config: {label: {value: {percent: true}}}
  * name: "legend:bottom", data: \three, config: {legend: {position: \bottom}}
]

dotc = (o = {}) -> {style: \dot, dot: ({motion: \none} <<< o)}
cases ++= [
  * name: "dot:circle", data: \two, config: dotc!
  * name: "dot:person", data: \three, config: dotc(shape: \person)
  * name: "dot:bug,ring", data: \ring, config: dotc(shape: \bug)
  * name: "dot:square,unit", data: \two, config: dotc(shape: \square, unit: 20)
  * name: "dot:records", data: \records, config: dotc(unit: 1)
]

# 閒置動態: 時鐘走了之後點的內層要有位移 ( 只看有沒有動, 不存 snapshot 的位置 )
cases.push do
  name: "dot:motion"
  data: \two
  config: {style: \dot, dot: {motion: \wander, shape: \bug}}
  steps: [(c) ->
    c.anim.step 500
    w = c.svg.querySelector 'g.dot > g.wig'
    if !(w and /rotate/.exec(w.getAttribute(\transform) or '')) => throw new Error("wander 沒有在動: #{w and w.getAttribute(\transform)}")
    # 位移跟時鐘起點有關, 有小數誤差. 確認有動之後清掉再存
    c.stop!
    c.svg.querySelectorAll('g.wig').forEach -> it.removeAttribute \transform
  ]

# 圖例關掉一個集合: 那個集合從每個區域拿掉, 點走到剩下的區域
cases.push do
  name: "legend:toggle"
  data: \three
  config: dotc!
  steps:
    * (c, ctx) ->
        c._ids = c.dots.map (.id)
        c.legend._picked["Juice"] = false
        c.bind!; c.resize!; c.render!
        ctx.snap \hidden
    * (c) ->
        if c.geo.circles.length != 2 => throw new Error("關掉之後應該剩兩個圓: #{c.geo.circles.length}")
        kept = c.dots.filter((d) -> d.id in c._ids).length
        if kept < c.dots.length * 0.9 => throw new Error("點應該保留身分, 只有 #kept / #{c.dots.length} 保留")

# 換格: 點保留身分. 2020 -> 2021 交集多了 100, 應該大多是從「僅 Trial」走過來的
cases.push do
  name: "frames:migrate"
  data: \frames
  config: dotc! <<< common: animation: autoplay: false
  steps:
    * (c, ctx) ->
        c.pause!
        c.seek {frame: 0, progress: 0.99}
        c.anim.flush!
        c._before = new Map(c.dots.map (d) -> [d.id, d.key])
        ctx.snap \frame0
    * (c) ->
        c.seek {frame: 1, progress: 0.99}
        c.anim.flush!
    * (c) ->
        moved = c.dots.filter((d) -> c._before.get(d.id) == "Trial" and d.key == "Paying & Trial").length
        if moved < 5 => throw new Error("應該有點從「僅 Trial」走進交集: #moved")

# 數值換算: inclusive 的 A = 總數, exclusive 的 A = 只屬於 A
region-is = (key, v) -> (c) ->
  r = c.geo.regions.find -> it.key == key
  if !(r and r.value == v) => throw new Error("#key 應為 #v: #{r and r.value}")
cases ++= [
  * name: "value:inclusive", data: \two, steps: [region-is("Trial users", 412), region-is("Paying users & Trial users", 168)]
  * name: "value:exclusive-calc", data: \exclusive, config: {value: \exclusive}, steps: [region-is("A", 40), region-is("A & B", 12)]
]

tabinfo-ok = (c) ->
  tab = c.mod.tabinfo or {}
  for k in <[circle label label/set label/value label/region dot legend tip]> =>
    if !tab[k] => throw new Error("tabinfo 少了 #k")
cases.push {name: "tabinfo", data: \two, steps: [tabinfo-ok]}

mctest.suite {data, cases, size: [520, 340]}
