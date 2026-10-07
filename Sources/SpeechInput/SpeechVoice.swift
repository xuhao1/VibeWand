import Foundation

/// A voice of the voice service: its name there, who it sounds like, and in a few words how. The lists are the
/// service's own, as its documentation gives them for each model; the words describing a voice are ours.
public struct SpeechVoice: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        /// Speaks Mandarin, and the other languages of its model, without a marked accent.
        case plain
        /// Speaks a Chinese dialect, or Mandarin with that region's accent.
        case dialect
        /// Speaks with the accent of another language, or speaks only that language.
        case foreign
        /// A child or a role.
        case character
    }
    /// What the service calls it: the value of its `voice` parameter.
    public let id: String
    /// Its name as the service gives it in Chinese.
    public let name: String
    public let female: Bool
    public let kind: Kind
    /// How it sounds, in Chinese and in English.
    public let sound: (zh: String, en: String)

    public static func == (a: SpeechVoice, b: SpeechVoice) -> Bool { a.id == b.id }

    private static func f(_ id: String, _ name: String, _ zh: String, _ en: String, _ kind: Kind = .plain) -> SpeechVoice {
        SpeechVoice(id: id, name: name, female: true, kind: kind, sound: (zh, en))
    }
    private static func m(_ id: String, _ name: String, _ zh: String, _ en: String, _ kind: Kind = .plain) -> SpeechVoice {
        SpeechVoice(id: id, name: name, female: false, kind: kind, sound: (zh, en))
    }

    /// The voice among `voices` that a name means: the service's name for it, however it is capitalised, or
    /// its Chinese one, which is what a model asked to change the voice sometimes gives.
    public static func named(_ name: String, in voices: [SpeechVoice]) -> SpeechVoice? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return voices.first { $0.id.lowercased() == wanted } ?? voices.first { $0.name.lowercased() == wanted }
    }

    /// The voices of the Omni model that hears a command and answers it, `qwen3.8-omni-flash-realtime`.
    public static let omni: [SpeechVoice] = [
        f("Tina", "甜甜", "甜美温暖", "sweet and warm"),
        f("Serena", "苏瑶", "温柔", "gentle"),
        f("Maia", "四月", "知性温柔", "thoughtful and gentle"),
        f("Liora Mira", "清欢", "温柔，有生活气", "gentle, homely"),
        f("Mia", "舒然", "细腻治愈", "delicate, soothing"),
        f("Katerina", "卡捷琳娜", "御姐，有韵味", "mature and poised"),
        f("Cici", "绵绵", "活泼可爱，软糯", "lively, soft"),
        f("Momo", "茉兔", "撒娇搞怪", "playful, coy"),
        f("longanlingxin", "龙安灵心", "知心温暖", "caring and warm"),
        f("Cindy", "林欣宜", "嗲，台湾口音", "coy, Taiwan accent"),
        f("Qiao", "小乔妹", "甜而有个性，台湾口音", "sweet with attitude, Taiwan accent"),
        f("Angel", "安琪", "很甜，略带台湾口音", "very sweet, slight Taiwan accent"),
        m("Raymond", "林川野", "清亮的年轻男声", "clear young man"),
        m("Evan", "江晨", "男大学生", "college boy"),
        m("Andre", "安德雷", "磁性沉稳", "magnetic, steady"),
        m("Zane", "泽恩", "低沉磁性", "deep, magnetic"),
        m("Theo Calm", "予安", "沉静疗愈", "calm, comforting"),
        m("Ryan", "甜茶", "有节奏，戏感强", "rhythmic, dramatic"),
        m("Wil", "伟伦", "港台腔小哥", "Hong Kong and Taiwan lilt"),
        m("Joyner", "阿逗", "搞笑夸张", "comic, exaggerated"),
        m("Gold", "金爷", "说唱味", "rapper"),
        m("Li Cassian", "李公公", "宫里的公公", "a palace eunuch", .character),
        f("Sunny", "晴儿", "四川话，甜", "Sichuan, sweet", .dialect),
        m("Eric", "程川", "四川话，市井", "Sichuan, breezy", .dialect),
        m("Dylan", "晓东", "北京话，胡同少年", "Beijing lad", .dialect),
        m("Peter", "李彼得", "天津话，相声捧哏", "Tianjin, crosstalk", .dialect),
        m("Marcus", "秦川", "陕西话，声沉", "Shaanxi, deep", .dialect),
        m("Li", "老李", "南京话，爱唠叨的伯伯", "Nanjing, grumbling uncle", .dialect),
        m("Joseph Chen", "阿樸伯", "闽南话，南洋老华侨", "Minnan, an old man", .dialect),
        m("Rocky", "阿强", "粤语，幽默", "Cantonese, witty", .dialect),
        f("Kiki", "阿清", "粤语，甜美", "Cantonese, sweet", .dialect),
        f("Jennifer", "詹妮弗", "美式英语，电影质感", "American English, cinematic", .foreign),
        m("Aiden", "艾登", "美式英语，大男孩", "American English, boyish", .foreign),
        f("Mione", "敏儿", "英式，成熟知性", "British, mature", .foreign),
        f("Ono Anna", "小野杏", "日本，鬼灵精怪", "Japanese, impish", .foreign),
        f("Sohee", "素熙", "韩国，温柔开朗", "Korean, warm", .foreign),
        m("Emilien", "埃米尔安", "法国，浪漫", "French, romantic", .foreign),
        m("Lenn", "莱恩", "德国，理性", "German, level-headed", .foreign),
        m("Dolce", "多尔切", "意大利，慵懒大叔", "Italian, laid-back", .foreign),
        m("Bodega", "博德加", "西班牙，热情大叔", "Spanish, hearty", .foreign),
        f("Sonrisa", "索尼莎", "拉美，热情开朗", "Latin American, outgoing", .foreign),
        m("Radio Gol", "拉迪奥·戈尔", "葡萄牙语，足球解说", "Portuguese, football commentator", .foreign),
        m("Alek", "阿列克", "俄罗斯，外冷内暖", "Russian, cool yet warm", .foreign),
        m("Jakub", "雅克", "波兰，磁性", "Polish, magnetic", .foreign),
        f("Eliška", "艾莉卡", "捷克，温润", "Czech, warm", .foreign),
        f("Griet", "海娜", "荷兰，成熟文艺", "Dutch, mature", .foreign),
        f("Siiri", "西芮", "芬兰，内敛舒缓", "Finnish, quiet and unhurried", .foreign),
        f("Ingrid", "林恩", "挪威，乡村姑娘", "Norwegian, country girl", .foreign),
        f("Sigga", "Sigga", "冰岛，知性", "Icelandic, thoughtful", .foreign),
        m("Arda", "阿尔达", "土耳其，干净温润", "Turkish, clean and mellow", .foreign),
        f("Roya", "萝雅", "爱运动，洒脱", "sporty, free-spirited", .foreign),
        f("Marina", "玛丽娜", "都市女孩", "city girl", .foreign),
        f("Hana", "阿幸", "越南，成熟", "Vietnamese, mature", .foreign),
        m("Rizky", "阿力", "印尼，有个性", "Indonesian, distinctive", .foreign),
        f("Bea", "雅娜", "菲律宾，甜", "Filipino, sweet", .foreign),
        f("Chloe", "思怡", "马来西亚，白领", "Malaysian, professional", .foreign)
    ]

    /// The voices of the synthesis model that reads lines out beside a model with no voice of its own,
    /// `qwen-audio-3.1-tts-flash`.
    public static let synthesis: [SpeechVoice] = [
        f("longanwen_v3.1", "龙安温", "优雅知性", "elegant, thoughtful"),
        f("longanli_v3.1", "龙安莉", "利落从容", "brisk, composed"),
        f("longxiaoxia_v3.1", "龙小夏", "沉稳权威", "steady, authoritative"),
        f("loongstella_v3.1", "loongstella", "飒爽利落", "crisp, brisk"),
        f("longyingtao_v3.1", "龙应桃", "温柔淡定", "gentle, composed"),
        f("longanya_v3.1", "龙安雅", "高雅", "refined"),
        f("longwan_v3.1", "龙婉", "细腻柔声", "soft, delicate"),
        f("longxing_v3.1", "龙星", "温婉邻家", "the girl next door"),
        f("longhua_v3.1", "龙华", "元气甜美", "lively, sweet"),
        f("longanlingxi_v3.1", "龙安灵希", "可爱甜美", "cute, sweet"),
        f("longyuan_v3.1", "龙媛", "温暖治愈", "warm, soothing"),
        f("longmiao_v3.1", "龙妙", "抑扬顿挫", "expressive"),
        f("yuxiaoyun_v3.1", "于小云", "元气亲切", "lively, friendly"),
        f("qiaoxiaojiao_v3.1", "乔小娇", "俏丽可爱", "pretty, cute"),
        f("xiaxiaochen_v3.1", "夏小晨", "元气明亮", "bright, energetic"),
        f("wenhuaiqing_v3.1", "温怀清", "清亮柔和", "clear, soft"),
        f("anxiaolan_v3.1", "安小岚", "清甜纯净", "sweet, pure"),
        f("xieshurou_v3.1", "谢舒柔", "柔和知性", "soft, thoughtful"),
        f("baiqinglan_v3.1", "白清岚", "明亮清纯", "bright, fresh"),
        f("xuyuyuan_v3.1", "许玉远", "知性成熟", "mature, polished"),
        f("anruorou_v3.1", "安若柔", "气声知性", "breathy, thoughtful"),
        f("wenhuaizhi_v3.1", "闻怀之", "稳重成熟", "steady, mature"),
        f("xiaoxingzhi_v3.1", "萧行之", "端庄贵气", "dignified"),
        f("guyunshu_v3.1", "顾云舒", "成熟稳重", "mature, steady"),
        f("yeqinghe_v3.1", "叶清禾", "亲切温柔", "kind, gentle"),
        f("yunhuanhuan_v3.1", "云欢欢", "高亢热情", "high, spirited"),
        f("xuxiaoqiao_v3.1", "徐小俏", "自然俏皮", "natural, playful"),
        f("baianran_v3.1", "白安然", "浑厚，带气声", "full, breathy"),
        f("xuyanchu_v3.1", "许言初", "沉稳磁性", "steady, magnetic"),
        f("yezhiqing_v3.1", "叶知晴", "轻快自然", "light, natural"),
        f("anyuqing_v3.1", "安语晴", "甜妹", "sweet girl"),
        f("longanhuan_v3.1", "龙安欢", "多语种", "many languages"),
        f("longanlingxin_v3.1", "龙安灵心", "多语种", "many languages"),
        f("longanfengyue_v3.1", "龙安风悦", "多语种", "many languages"),
        m("longanlang_v3.1", "龙安朗", "清爽利落", "fresh, brisk"),
        m("longanzhi_v3.1", "龙安智", "睿智轻熟", "wise, mature"),
        m("longsanshu_v3.1", "龙三叔", "沉稳，有质感", "steady, textured"),
        m("longanyang_v3.1", "龙安洋", "阳光大男孩", "sunny, boyish"),
        m("longhan_v3.1", "龙寒", "温暖深情", "warm, devoted"),
        m("longzhe_v3.1", "龙哲", "憨厚暖男", "plain and warm"),
        m("anmingyuan_v3.1", "安明远", "清亮自然", "clear, natural"),
        m("huozhuoshi_v3.1", "霍拙石", "清亮", "clear"),
        m("andi_v3.1", "安迪", "带美式口音", "American-born accent"),
        m("xunanchuan_v3.1", "许南川", "多语种", "many languages"),
        m("longanchong_v3.1", "龙安冲", "激情带货", "high-energy salesman"),
        f("Emily_v3.1", "Emily", "英式英语", "British English", .foreign),
        f("Luna_v3.1", "Luna", "英式英语", "British English", .foreign),
        m("Eric_v3.1", "Eric", "英式英语", "British English", .foreign),
        m("Luca_v3.1", "Luca", "英式英语", "British English", .foreign),
        f("Abby_v3.1", "Abby", "美式英语", "American English", .foreign),
        f("Annie_v3.1", "Annie", "美式英语", "American English", .foreign),
        f("Ava_v3.1", "Ava", "美式英语", "American English", .foreign),
        f("Beth_v3.1", "Beth", "美式英语", "American English", .foreign),
        f("Betty_v3.1", "Betty", "美式英语", "American English", .foreign),
        f("Cally_v3.1", "Cally", "美式英语", "American English", .foreign),
        f("Cindy_v3.1", "Cindy", "美式英语", "American English", .foreign),
        f("Donna_v3.1", "Donna", "美式英语", "American English", .foreign),
        m("Andy_v3.1", "Andy", "美式英语", "American English", .foreign),
        m("Brian_v3.1", "Brian", "美式英语", "American English", .foreign),
        m("David_v3.1", "David", "美式英语", "American English", .foreign),
        f("longanyuanfei_v3.1", "龙安元妃", "高傲的妃子", "a haughty consort", .character),
        m("libai_v3.1", "李白", "古代诗仙", "a poet of old", .character),
        m("longhuohuo_v3.1", "龙火火", "顽皮少年", "a cheeky boy", .character),
        m("longjielidou_v3.1", "龙杰力豆", "天真男童", "a little boy", .character),
        m("longniuniu_v3.1", "龙牛牛", "阳光男童", "a sunny little boy", .character),
        m("longshanshan_v3.1", "龙闪闪", "戏剧化的童声", "a theatrical child", .character),
        f("longling_v3.1", "龙铃", "稚气童声", "a little girl", .character),
        f("longpaopao_v3.1", "龙泡泡", "软萌童声", "a bubbly child", .character)
    ]
}
