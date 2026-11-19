#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""iPhone 改定位(Windows / Mac 通用,自用)

用法:
  不带参数              进入提问模式,输入国家或城市名即可
  set 英国              按国家设定位(用该国的默认城市)
  set 洛杉矶            按城市设定位
  set 美国洛杉矶        国家+城市(同名城市时用来区分)
  set 51.5074 -0.1278   按经纬度设定位(纬度在前)
  list                  列出支持的国家和城市
  clear                 手动恢复真实定位
  setup                 新手机第一次用:让"开发者模式"开关显示出来
  check                 检查工具、手机连接、开发者模式是否就绪

定位在本窗口运行期间保持,按 Ctrl+C 结束并恢复真实定位。
需要先安装: Python 3.9+ 和 pymobiledevice3。
"""
import importlib.util
import json
import subprocess
import sys

PMD3 = [sys.executable, "-m", "pymobiledevice3"]
IS_WINDOWS = sys.platform.startswith("win")
INSTALL_CMD = "py -m pip install -U pymobiledevice3" if IS_WINDOWS else "pip3 install -U pymobiledevice3"

# 地点表。
# 顶格的行是国家/地区:  分组|中文名|英文别名(逗号分隔)
# 缩进的行是城市:        中文名|纬度|经度|英文别名(逗号分隔)
# 每个国家的第一个城市是"只输入国家名"时的默认城市。
# 想加城市:照着格式在对应国家下面加一行即可。
DATA = """
欧洲|英国|uk,britain,england,unitedkingdom
  伦敦|51.5074|-0.1278|london
  曼彻斯特|53.4808|-2.2426|manchester
  伯明翰|52.4862|-1.8904|birmingham
  爱丁堡|55.9533|-3.1883|edinburgh
  利物浦|53.4084|-2.9916|liverpool
  格拉斯哥|55.8642|-4.2518|glasgow
  利兹|53.8008|-1.5491|leeds
  布里斯托|51.4545|-2.5879|bristol
  剑桥|52.2053|0.1218|cambridge
  牛津|51.7520|-1.2577|oxford
欧洲|法国|france
  巴黎|48.8566|2.3522|paris
  马赛|43.2965|5.3698|marseille
  里昂|45.7640|4.8357|lyon
  尼斯|43.7102|7.2620|nice
  图卢兹|43.6047|1.4442|toulouse
  波尔多|44.8378|-0.5792|bordeaux
欧洲|德国|germany
  柏林|52.5200|13.4050|berlin
  慕尼黑|48.1351|11.5820|munich
  法兰克福|50.1109|8.6821|frankfurt
  汉堡|53.5511|9.9937|hamburg
  科隆|50.9375|6.9603|cologne
  杜塞尔多夫|51.2277|6.7735|dusseldorf
  斯图加特|48.7758|9.1829|stuttgart
欧洲|意大利|italy
  罗马|41.9028|12.4964|rome
  米兰|45.4642|9.1900|milan
  威尼斯|45.4408|12.3155|venice
  佛罗伦萨|43.7696|11.2558|florence
  那不勒斯|40.8518|14.2681|naples
  都灵|45.0703|7.6869|turin
欧洲|西班牙|spain
  马德里|40.4168|-3.7038|madrid
  巴塞罗那|41.3851|2.1734|barcelona
  瓦伦西亚|39.4699|-0.3763|valencia
  塞维利亚|37.3891|-5.9845|seville
欧洲|荷兰|netherlands,holland
  阿姆斯特丹|52.3676|4.9041|amsterdam
  鹿特丹|51.9244|4.4777|rotterdam
  海牙|52.0705|4.3007|thehague,hague
欧洲|瑞士|switzerland
  苏黎世|47.3769|8.5417|zurich
  日内瓦|46.2044|6.1432|geneva
  伯尔尼|46.9480|7.4474|bern
欧洲|俄罗斯|russia
  莫斯科|55.7558|37.6173|moscow
  圣彼得堡|59.9343|30.3351|saintpetersburg,stpetersburg
欧洲|瑞典|sweden
  斯德哥尔摩|59.3293|18.0686|stockholm
  哥德堡|57.7089|11.9746|gothenburg
欧洲|挪威|norway
  奥斯陆|59.9139|10.7522|oslo
欧洲|丹麦|denmark
  哥本哈根|55.6761|12.5683|copenhagen
欧洲|芬兰|finland
  赫尔辛基|60.1699|24.9384|helsinki
欧洲|波兰|poland
  华沙|52.2297|21.0122|warsaw
  克拉科夫|50.0647|19.9450|krakow
欧洲|爱尔兰|ireland
  都柏林|53.3498|-6.2603|dublin
欧洲|葡萄牙|portugal
  里斯本|38.7223|-9.1393|lisbon
  波尔图|41.1579|-8.6291|porto
欧洲|比利时|belgium
  布鲁塞尔|50.8503|4.3517|brussels
欧洲|奥地利|austria
  维也纳|48.2082|16.3738|vienna
欧洲|希腊|greece
  雅典|37.9838|23.7275|athens
欧洲|捷克|czech,czechia
  布拉格|50.0755|14.4378|prague
欧洲|匈牙利|hungary
  布达佩斯|47.4979|19.0402|budapest
欧洲|土耳其|turkey
  伊斯坦布尔|41.0082|28.9784|istanbul
  安卡拉|39.9334|32.8597|ankara
欧洲|乌克兰|ukraine
  基辅|50.4501|30.5234|kyiv,kiev
美洲|美国|usa,us,america,unitedstates
  纽约|40.7128|-74.0060|newyork,nyc
  洛杉矶|34.0522|-118.2437|losangeles,la
  旧金山|37.7749|-122.4194|sanfrancisco,sf
  芝加哥|41.8781|-87.6298|chicago
  华盛顿|38.9072|-77.0369|washington,dc,washingtondc
  西雅图|47.6062|-122.3321|seattle
  波士顿|42.3601|-71.0589|boston
  休斯敦|29.7604|-95.3698|houston
  达拉斯|32.7767|-96.7970|dallas
  迈阿密|25.7617|-80.1918|miami
  拉斯维加斯|36.1699|-115.1398|lasvegas,vegas
  圣迭戈|32.7157|-117.1611|sandiego
  圣何塞|37.3382|-121.8863|sanjose
  费城|39.9526|-75.1652|philadelphia
  亚特兰大|33.7490|-84.3880|atlanta
  丹佛|39.7392|-104.9903|denver
  凤凰城|33.4484|-112.0740|phoenix
  檀香山|21.3069|-157.8583|honolulu,hawaii,夏威夷
美洲|加拿大|canada
  多伦多|43.6532|-79.3832|toronto
  温哥华|49.2827|-123.1207|vancouver
  蒙特利尔|45.5017|-73.5673|montreal
  渥太华|45.4215|-75.6972|ottawa
  卡尔加里|51.0447|-114.0719|calgary
美洲|墨西哥|mexico
  墨西哥城|19.4326|-99.1332|mexicocity
  坎昆|21.1619|-86.8515|cancun
美洲|巴西|brazil
  圣保罗|-23.5505|-46.6333|saopaulo
  里约热内卢|-22.9068|-43.1729|riodejaneiro,rio,里约
  巴西利亚|-15.7939|-47.8828|brasilia
美洲|阿根廷|argentina
  布宜诺斯艾利斯|-34.6037|-58.3816|buenosaires
美洲|智利|chile
  圣地亚哥|-33.4489|-70.6693|santiago
美洲|哥伦比亚|colombia
  波哥大|4.7110|-74.0721|bogota
美洲|秘鲁|peru
  利马|-12.0464|-77.0428|lima
亚洲/中东|中国|china
  北京|39.9042|116.4074|beijing
  上海|31.2304|121.4737|shanghai
  广州|23.1291|113.2644|guangzhou
  深圳|22.5431|114.0579|shenzhen
  成都|30.5728|104.0668|chengdu
  杭州|30.2741|120.1551|hangzhou
  重庆|29.5630|106.5516|chongqing
  武汉|30.5928|114.3055|wuhan
  西安|34.3416|108.9398|xian
  南京|32.0603|118.7969|nanjing
亚洲/中东|香港|hongkong,hk
  香港|22.3193|114.1694|
亚洲/中东|澳门|macau,macao
  澳门|22.1987|113.5439|
亚洲/中东|台湾|taiwan
  台北|25.0330|121.5654|taipei
  高雄|22.6273|120.3014|kaohsiung
亚洲/中东|日本|japan
  东京|35.6762|139.6503|tokyo
  大阪|34.6937|135.5023|osaka
  京都|35.0116|135.7681|kyoto
  横滨|35.4437|139.6380|yokohama
  名古屋|35.1815|136.9066|nagoya
  福冈|33.5902|130.4017|fukuoka
  札幌|43.0618|141.3545|sapporo
  冲绳|26.2124|127.6809|okinawa,naha,那霸
亚洲/中东|韩国|korea,southkorea
  首尔|37.5665|126.9780|seoul
  釜山|35.1796|129.0756|busan
  济州|33.4996|126.5312|jeju,济州岛
亚洲/中东|印度|india
  新德里|28.6139|77.2090|newdelhi,delhi
  孟买|19.0760|72.8777|mumbai
  班加罗尔|12.9716|77.5946|bangalore,bengaluru
亚洲/中东|新加坡|singapore
  新加坡|1.3521|103.8198|
亚洲/中东|泰国|thailand
  曼谷|13.7563|100.5018|bangkok
  清迈|18.7883|98.9853|chiangmai
  普吉|7.8804|98.3923|phuket,普吉岛
亚洲/中东|马来西亚|malaysia
  吉隆坡|3.1390|101.6869|kualalumpur,kl
  槟城|5.4141|100.3288|penang
亚洲/中东|印度尼西亚|indonesia,印尼
  雅加达|-6.2088|106.8456|jakarta
  巴厘岛|-8.6705|115.2126|bali,denpasar
亚洲/中东|越南|vietnam
  河内|21.0278|105.8342|hanoi
  胡志明市|10.8231|106.6297|hochiminh,saigon,胡志明,西贡
亚洲/中东|菲律宾|philippines
  马尼拉|14.5995|120.9842|manila
  宿务|10.3157|123.8854|cebu
亚洲/中东|阿联酋|uae
  迪拜|25.2048|55.2708|dubai
  阿布扎比|24.4539|54.3773|abudhabi
亚洲/中东|沙特|saudi,saudiarabia,沙特阿拉伯
  利雅得|24.7136|46.6753|riyadh
  吉达|21.4858|39.1925|jeddah
亚洲/中东|卡塔尔|qatar
  多哈|25.2854|51.5310|doha
亚洲/中东|以色列|israel
  特拉维夫|32.0853|34.7818|telaviv
亚洲/中东|巴基斯坦|pakistan
  伊斯兰堡|33.6844|73.0479|islamabad
  卡拉奇|24.8607|67.0011|karachi
大洋洲|澳大利亚|australia,澳洲
  悉尼|-33.8688|151.2093|sydney
  墨尔本|-37.8136|144.9631|melbourne
  布里斯班|-27.4698|153.0251|brisbane
  珀斯|-31.9505|115.8605|perth
  阿德莱德|-34.9285|138.6007|adelaide
  堪培拉|-35.2809|149.1300|canberra
大洋洲|新西兰|newzealand
  奥克兰|-36.8485|174.7633|auckland
  惠灵顿|-41.2865|174.7762|wellington
非洲|南非|southafrica
  约翰内斯堡|-26.2041|28.0473|johannesburg
  开普敦|-33.9249|18.4241|capetown
非洲|埃及|egypt
  开罗|30.0444|31.2357|cairo
非洲|尼日利亚|nigeria
  拉各斯|6.5244|3.3792|lagos
非洲|肯尼亚|kenya
  内罗毕|-1.2921|36.8219|nairobi
非洲|摩洛哥|morocco
  卡萨布兰卡|33.5731|-7.5898|casablanca
"""


def normalize(text):
    return "".join(text.split()).lower()


def _split_names(first, extra):
    names = [first.strip()]
    names += [a.strip() for a in extra.split(",") if a.strip()]
    return names


def _load():
    """把 DATA 解析成国家列表和查找表。"""
    countries = []  # [{"group", "name", "names", "cities": [{"name","names","lat","lon"}]}]
    for raw in DATA.splitlines():
        if not raw.strip():
            continue
        fields = raw.strip().split("|")
        if raw[0] not in (" ", "\t"):
            countries.append({
                "group": fields[0],
                "name": fields[1],
                "names": _split_names(fields[1], fields[2] if len(fields) > 2 else ""),
                "cities": [],
            })
        else:
            countries[-1]["cities"].append({
                "name": fields[0],
                "lat": float(fields[1]),
                "lon": float(fields[2]),
                "names": _split_names(fields[0], fields[3] if len(fields) > 3 else ""),
            })

    lookup = {}

    def label_of(country, city):
        if city["name"] == country["name"]:
            return city["name"]
        return country["name"] + " " + city["name"]

    def add(key, country, city):
        lookup.setdefault(normalize(key), (label_of(country, city), city["lat"], city["lon"]))

    # 先登记国家名(指向默认城市),再登记城市名,最后登记"国家+城市"
    for country in countries:
        for name in country["names"]:
            add(name, country, country["cities"][0])
    for country in countries:
        for city in country["cities"]:
            for name in city["names"]:
                add(name, country, city)
    for country in countries:
        for city in country["cities"]:
            for cname in country["names"]:
                for name in city["names"]:
                    add(cname + name, country, city)
    return countries, lookup


COUNTRIES, LOOKUP = _load()


def resolve(words):
    """把用户输入解析成 (显示名, 纬度, 经度);解析不了返回 None。"""
    text = " ".join(words).replace(",", " ").replace("，", " ")
    parts = text.split()
    if len(parts) == 2:
        try:
            lat, lon = float(parts[0]), float(parts[1])
        except ValueError:
            pass
        else:
            if -90 <= lat <= 90 and -180 <= lon <= 180:
                return ("自定义坐标", lat, lon)
            return None
    return LOOKUP.get(normalize(text))


def suggest(text, limit=8):
    """找不到时,给出名字相近的地点。"""
    key = normalize(text)
    if not key:
        return []
    found = []
    for name, (label, _lat, _lon) in LOOKUP.items():
        long_enough = len(name) >= (4 if name.isascii() else 2)
        if key in name or (long_enough and name in key):
            if label not in found:
                found.append(label)
    return found[:limit]


def explain_not_found(text):
    print("没找到 \"" + text + "\"。")
    similar = suggest(text)
    if similar:
        print("你是不是想找: " + "、".join(similar))
    print("输入 list 查看支持的国家和城市,或直接输入经纬度,例如 51.5074 -0.1278")


def run_capture(args, timeout=300):
    """运行 pymobiledevice3 子命令,返回 (退出码, 输出文字)。"""
    try:
        done = subprocess.run(
            PMD3 + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return 1, "超时"
    return done.returncode, done.stdout.decode("utf-8", errors="replace")


def tool_installed():
    return importlib.util.find_spec("pymobiledevice3") is not None


def device_connected():
    _code, out = run_capture(["usbmux", "list"], timeout=60)
    start = out.find("[")
    if start >= 0:
        try:
            return len(json.loads(out[start:])) > 0
        except ValueError:
            pass
    return "DeviceClass" in out


def developer_mode_on():
    _code, out = run_capture(["amfi", "developer-mode-status"], timeout=60)
    lines = [line.strip() for line in out.splitlines() if line.strip()]
    return bool(lines) and lines[-1].lower() == "true"


def explain_no_device():
    print("没有认到手机。请依次检查:")
    print("  1. 手机用数据线连着电脑,并且已经解锁;")
    print("  2. 手机上点过\"信任此电脑\";")
    print("  3. 换一根能传数据的线,或拔掉重插。")
    if IS_WINDOWS:
        print("  4. Windows 需要先安装\"Apple 设备\"(微软商店)或 iTunes。")


def explain_developer_mode_off():
    print("手机的\"开发者模式\"还没打开。请先运行一次首次设置:")
    print("  在提问模式里输入 setup,或运行: ios_loc.py setup")


def cmd_check():
    print("工具 pymobiledevice3: 已安装")
    if not device_connected():
        explain_no_device()
        return 1
    print("手机连接: 已认到")
    if not developer_mode_on():
        explain_developer_mode_off()
        return 1
    print("开发者模式: 已打开")
    print("一切就绪,可以设定位了。")
    return 0


def cmd_setup():
    if not device_connected():
        explain_no_device()
        return 1
    if developer_mode_on():
        print("这台手机的开发者模式已经打开,不需要再设置。")
        return 0
    code, out = run_capture(["amfi", "reveal-developer-mode"], timeout=60)
    if code != 0:
        print("让开关显示出来时出错:")
        print(out.strip())
        return 1
    print("已让\"开发者模式\"开关显示出来。接下来在手机上操作:")
    print("  1. 把\"设置\"从后台划掉,重新打开;")
    print("  2. 设置 → 隐私与安全性 → 滑到最底下 → 开发者模式 → 打开;")
    print("  3. 按提示重启手机(数据线不用拔);")
    print("  4. 开机解锁后在弹窗里点\"打开\",输入锁屏密码;")
    print("  5. 确认 设置 → 隐私与安全性 → 定位服务 是打开的。")
    print("做完后再来设定位。")
    return 0


def cmd_clear():
    code, out = run_capture(["developer", "dvt", "simulate-location", "clear"], timeout=120)
    if code != 0:
        print("恢复真实定位时出错:")
        print(out.strip())
        return 1
    print("已恢复真实定位")
    return 0


def cmd_list():
    current = None
    for country in COUNTRIES:
        if country["group"] != current:
            current = country["group"]
            print()
            print("[" + current + "]")
        cities = [c["name"] for c in country["cities"]]
        if cities == [country["name"]]:
            print("  " + country["name"])
        else:
            print("  " + country["name"] + ": " + "、".join(cities))
    print()
    print("怎么输入:")
    print("  只输国家     英国        → 用该国第一个城市(上面每行最前面那个)")
    print("  只输城市     洛杉矶")
    print("  国家+城市    美国洛杉矶   (中间加不加空格都行)")
    print("  英文也可以   uk / losangeles / la")
    print("  经纬度       51.5074 -0.1278")
    return 0


def cmd_set(label, lat, lon):
    print("正在检查手机…")
    if not device_connected():
        explain_no_device()
        return 1
    if not developer_mode_on():
        explain_developer_mode_off()
        return 1
    # 手机重启后镜像需要重新挂载;已挂载时这一步很快结束
    run_capture(["mounter", "auto-mount"], timeout=600)

    print("正在把定位设为: " + label + " (" + str(lat) + ", " + str(lon) + ")")
    print("保持此窗口开着,定位就一直有效;按 Ctrl+C 结束并恢复真实定位。")
    proc = subprocess.Popen(
        PMD3 + ["developer", "dvt", "simulate-location", "set", "--", str(lat), str(lon)]
    )
    interrupted = False
    try:
        code = proc.wait()
    except KeyboardInterrupt:
        interrupted = True
        code = 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                proc.kill()
    if not interrupted and code != 0:
        print("定位命令提前结束了(退出码 " + str(code) + "),请看上面的报错信息。")
    print()
    print("正在恢复真实定位…")
    try:
        cmd_clear()
    except KeyboardInterrupt:
        print("已中断。如需恢复真实定位,可运行: ios_loc.py clear")
    return 0 if interrupted or code == 0 else 1


def interactive():
    print("iPhone 改定位")
    print("输入国家或城市名设定位,例如: 英国 / 洛杉矶 / 美国洛杉矶")
    print("其他可输入的内容:")
    print("  list  查看支持的国家和城市    setup  新手机首次设置")
    print("  check 检查是否就绪            直接回车  退出")
    while True:
        print()
        try:
            text = input("请输入: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if not text:
            return 0
        command = text.lower()
        if command in ("list", "名单"):
            cmd_list()
        elif command == "setup":
            cmd_setup()
        elif command == "check":
            cmd_check()
        elif command == "clear":
            cmd_clear()
        else:
            target = resolve([text])
            if target is None:
                explain_not_found(text)
            else:
                cmd_set(*target)


def main(argv):
    # 让提示文字立刻显示,不被缓冲打乱顺序
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except (AttributeError, ValueError):
        pass
    if not tool_installed():
        print("还没有安装 pymobiledevice3。请先运行:")
        print("  " + INSTALL_CMD)
        return 1
    if not argv:
        return interactive()
    command = argv[0].lower()
    if command in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    if command == "list":
        return cmd_list()
    if command == "clear":
        return cmd_clear()
    if command == "setup":
        return cmd_setup()
    if command == "check":
        return cmd_check()
    words = argv[1:] if command == "set" else argv
    if not words:
        print(__doc__)
        return 1
    target = resolve(words)
    if target is None:
        explain_not_found(" ".join(words))
        return 1
    return cmd_set(*target)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
