import Foundation

enum DebugResearchDemoData {
    static let demo: DebugResearchDataset = {
        let participants = [
            DebugResearchParticipant(id: "p0", name: "Ayşe", role: "Ürün yöneticisi", usageGroup: "Yoğun kullanıcı"),
            DebugResearchParticipant(id: "p1", name: "Fatma", role: "Öğretmen", usageGroup: "Temkinli kullanıcı"),
            DebugResearchParticipant(id: "p2", name: "Burak", role: "UX tasarımcısı", usageGroup: "Yoğun kullanıcı"),
            DebugResearchParticipant(id: "p3", name: "Deniz", role: "İletişim uzmanı", usageGroup: "Yeni kullanıcı"),
            DebugResearchParticipant(id: "p4", name: "Ece", role: "Araştırmacı", usageGroup: "Yoğun kullanıcı"),
            DebugResearchParticipant(id: "p5", name: "Kerem", role: "Yazılım geliştirici", usageGroup: "Yoğun kullanıcı"),
            DebugResearchParticipant(id: "p6", name: "Selin", role: "İnsan kaynakları", usageGroup: "Temkinli kullanıcı"),
            DebugResearchParticipant(id: "p7", name: "Mert", role: "Danışman", usageGroup: "Yeni kullanıcı")
        ]

        let codebook = [
            DebugCodebookEntry(
                id: "helper", name: "Araç / yardımcı", parentID: nil, status: .active,
                definition: "Yapay zekânın insanın belirlediği işi kolaylaştıran veya hızlandıran işlevsel bir araç olarak kurulması.",
                includeWhen: "Katılımcı kontrolün insanda kaldığını ve teknolojinin destekleyici rolünü vurguladığında.",
                excludeWhen: "Yapay zekâ karşılıklı fikir üreten özerk bir ortak gibi anlatıldığında.",
                example: "Benim için hızlı çalışan bir yardımcı; son kararı yine ben veriyorum.", revision: 3, colorIndex: 0
            ),
            DebugCodebookEntry(
                id: "speed", name: "Hızlandırma", parentID: "helper", status: .active,
                definition: "Teknolojinin süreyi kısaltması veya rutin işi azaltması.",
                includeWhen: "Zaman kazanma, ilk taslak veya otomasyon açıkça anıldığında.",
                excludeWhen: "Yalnızca çıktı kalitesinden söz edildiğinde.",
                example: "İlk taslağı dakikalar içinde çıkarıyor.", revision: 2, colorIndex: 0
            ),
            DebugCodebookEntry(
                id: "doublecheck", name: "Kontrol / double check", parentID: "helper", status: .review,
                definition: "Yapay zekâ çıktısının insan tarafından doğrulanması ve son kararın kullanıcıda tutulması.",
                includeWhen: "Kontrol etme, kaynak doğrulama veya düzeltme pratiği anlatıldığında.",
                excludeWhen: "Genel güvensizlik var ancak bir kontrol pratiği belirtilmiyorsa.",
                example: "Kullanıyorum ama bütün bilgileri iki kez kontrol ediyorum.", revision: 4, colorIndex: 0
            ),
            DebugCodebookEntry(
                id: "partner", name: "İş ortağı", parentID: nil, status: .active,
                definition: "Yapay zekânın karşılıklı düşünme ve üretme sürecine katılan bir ortak olarak kurulması.",
                includeWhen: "Karşılıklı fikir geliştirme, birlikte üretme veya düşünceyi açma anlatıldığında.",
                excludeWhen: "Tek yönlü komut ve iş tamamlama ilişkisi anlatıldığında.",
                example: "Fikri birlikte büyüttüğüm bir ekip arkadaşı gibi.", revision: 3, colorIndex: 1
            ),
            DebugCodebookEntry(
                id: "dialogue", name: "Diyalogla düşünme", parentID: "partner", status: .draft,
                definition: "Düşüncenin soru-cevap ve karşılıklı geri bildirim yoluyla geliştirilmesi.",
                includeWhen: "Katılımcı sohbetin kendi düşünmesini dönüştürdüğünü söylediğinde.",
                excludeWhen: "Sadece hazır yanıt alma anlatıldığında.",
                example: "Soruları cevapladıkça ben de ne düşündüğümü fark ediyorum.", revision: 1, colorIndex: 1
            ),
            DebugCodebookEntry(
                id: "mind", name: "İnsansı zihin", parentID: nil, status: .review,
                definition: "Sisteme düşünme, anlama veya niyet gibi insansı zihinsel özelliklerin atfedilmesi.",
                includeWhen: "Beni anlıyor, düşünüyor veya niyetimi seziyor gibi ifadeler bulunduğunda.",
                excludeWhen: "İnsansı dil yalnızca benzetme amacıyla ve açık mesafeyle kullanıldığında.",
                example: "Bazen gerçekten ne demek istediğimi anladığını düşünüyorum.", revision: 2, colorIndex: 2
            ),
            DebugCodebookEntry(
                id: "threat", name: "Tehdit / kontrol kaybı", parentID: nil, status: .active,
                definition: "Teknolojinin karar, emek veya mesleki özerklik üzerindeki olası kaybı olarak kurulması.",
                includeWhen: "Yerini alma, bağımlılaştırma ya da kontrolü ele geçirme kaygısı ifade edildiğinde.",
                excludeWhen: "Sorun yalnızca yanlış bilgi veya şeffaflık eksikliği olduğunda.",
                example: "Bir süre sonra kararı benim yerime vermesinden çekiniyorum.", revision: 3, colorIndex: 3
            ),
            DebugCodebookEntry(
                id: "blackbox", name: "Kara kutu", parentID: nil, status: .active,
                definition: "Çıktının nasıl üretildiğinin veya hangi kaynağa dayandığının görülememesi.",
                includeWhen: "Kaynak, gerekçe, veri veya işleyiş şeffaflığı sorgulandığında.",
                excludeWhen: "Şeffaflıkla bağlantısı kurulmadan genel güvensizlik dile getirildiğinde.",
                example: "Cevabı veriyor ama oraya nasıl vardığını göremiyorum.", revision: 2, colorIndex: 4
            )
        ]

        let excerpts = [
            DebugResearchExcerpt(id: "e01", participantID: "p0", time: "02:14–02:32", text: "İlk taslağı çok hızlı çıkarıyor ama son kararı ben veriyorum.", codeIDs: ["helper", "speed", "doublecheck"], analyticMemo: "Hız kazancı insan denetimiyle sınırlandırılıyor."),
            DebugResearchExcerpt(id: "e02", participantID: "p0", time: "08:01–08:24", text: "Fikri karşılıklı konuşarak büyütmek ekip arkadaşıyla çalışmaya benziyor.", codeIDs: ["partner", "dialogue"], analyticMemo: "Araçtan ortaklığa kayan ilişki."),
            DebugResearchExcerpt(id: "e03", participantID: "p1", time: "04:11–04:39", text: "Öğrencinin yerine düşünmesinden korkuyorum; bu nedenle önerdiği şeyi mutlaka kontrol ediyorum.", codeIDs: ["threat", "doublecheck"], analyticMemo: "Pedagojik özerklik kaygısı kontrol pratiği üretiyor."),
            DebugResearchExcerpt(id: "e04", participantID: "p1", time: "11:07–11:29", text: "Kaynağı nereden aldığını bilmediğimde cevabı sınıfta kullanamam.", codeIDs: ["blackbox", "threat"], analyticMemo: "Şeffaflık eksikliği kullanım sınırına dönüşüyor."),
            DebugResearchExcerpt(id: "e05", participantID: "p2", time: "03:46–04:06", text: "Bir ekran üretmekten çok, bana soru soran bir tasarım ortağı gibi davranıyor.", codeIDs: ["partner", "dialogue", "mind"], analyticMemo: "Diyalog, ortaklık ve insansı atıf aynı alıntıda birleşiyor."),
            DebugResearchExcerpt(id: "e06", participantID: "p2", time: "09:20–09:42", text: "Bazen niyetimi benden önce yakalıyor gibi geliyor.", codeIDs: ["mind"], analyticMemo: "Güçlü insansı zihin atfı."),
            DebugResearchExcerpt(id: "e07", participantID: "p3", time: "01:32–01:58", text: "Şimdilik yalnızca metni kısaltan pratik bir araç olarak kullanıyorum.", codeIDs: ["helper", "speed"], analyticMemo: "Yeni kullanıcıda kontrollü ve dar kullanım."),
            DebugResearchExcerpt(id: "e08", participantID: "p3", time: "06:15–06:44", text: "Doğru gibi yazdığı için nereden geldiğini fark etmek zor oluyor.", codeIDs: ["blackbox"], analyticMemo: "Akıcı dil, opaklığı görünmezleştiriyor."),
            DebugResearchExcerpt(id: "e09", participantID: "p4", time: "05:04–05:27", text: "Kodlama sırasında yeni bir örüntü önerdiğinde düşüncemi gerçekten açıyor.", codeIDs: ["partner", "dialogue"], analyticMemo: "Araştırmacı düşüncesini genişleten epistemik ortaklık."),
            DebugResearchExcerpt(id: "e10", participantID: "p4", time: "13:50–14:21", text: "Önerisini veriyle yeniden karşılaştırmadan tema olarak kabul etmem.", codeIDs: ["doublecheck", "blackbox"], analyticMemo: "Kanıta dönüş zorunluluğu."),
            DebugResearchExcerpt(id: "e11", participantID: "p5", time: "02:40–03:03", text: "Tekrarlı işi otomatikleştiren hızlı bir yardımcı, hepsi bu.", codeIDs: ["helper", "speed"], analyticMemo: "Bilinçli biçimde insansı atfı reddediyor."),
            DebugResearchExcerpt(id: "e12", participantID: "p5", time: "10:12–10:39", text: "Sistem büyüdükçe hangi verinin kararı etkilediğini izlemek zorlaşıyor.", codeIDs: ["blackbox", "threat"], analyticMemo: "Teknik opaklık kontrol kaybı kaygısına bağlanıyor."),
            DebugResearchExcerpt(id: "e13", participantID: "p6", time: "03:18–03:49", text: "Adaylar hakkında öneri verebilir ama insanla ilgili son kararı ona bırakamam.", codeIDs: ["helper", "threat", "doublecheck"], analyticMemo: "Yüksek riskli bağlamda araç rolü kesin biçimde sınırlandırılıyor."),
            DebugResearchExcerpt(id: "e14", participantID: "p6", time: "07:41–08:02", text: "Bazen çok anlayışlı cevap veriyor ama bunun gerçekten anlama olmadığını biliyorum.", codeIDs: ["mind"], analyticMemo: "İnsansı deneyim ile analitik mesafe birlikte."),
            DebugResearchExcerpt(id: "e15", participantID: "p7", time: "01:55–02:19", text: "Bana seçenek çıkarırsa yardımcı olur; kendi başına yön vermesi rahatsız eder.", codeIDs: ["helper", "threat"], analyticMemo: "Yardım ile yönlendirme arasında sınır çiziliyor."),
            DebugResearchExcerpt(id: "e16", participantID: "p7", time: "05:33–05:59", text: "Sorularına cevap verirken kendi fikrimi daha net kuruyorum.", codeIDs: ["partner", "dialogue"], analyticMemo: "Diyalog düşünsel açıklık sağlıyor."),
            DebugResearchExcerpt(id: "e17", participantID: "p0", time: "15:02–15:21", text: "Bazen kontrol etmeyi bırakıp doğrudan önerisini kullandığım da oluyor.", codeIDs: ["partner"], analyticMemo: "Kontrollü ortaklık temasını sınırlandıran teslimiyet anı."),
            DebugResearchExcerpt(id: "e18", participantID: "p5", time: "17:10–17:35", text: "Nasıl çalıştığını bilmesem de sonuç doğruysa benim için yeterli olabilir.", codeIDs: ["helper"], analyticMemo: "Opaklığın her katılımcı için sorun olmadığını gösteren karşıt örnek.")
        ]

        let candidateThemes = [
            DebugCandidateTheme(
                id: "controlled-partnership", title: "Kontrollü ortaklık", stage: .review,
                centralConcept: "Katılımcılar yapay zekânın üretken katkısını kabul ederken karar yetkisini insanda tutan bir ilişki kuruyor.",
                scope: "Araç, iş ortağı ve kontrol pratiklerinin birlikte görüldüğü anlatılar. Yalnız hız vurgusu bulunan ifadeler tek başına yeterli değil.",
                codeIDs: ["helper", "partner", "doublecheck", "dialogue"],
                evidenceIDs: ["e01", "e02", "e03", "e05", "e09", "e10", "e13", "e15", "e16"],
                contradictoryEvidenceIDs: ["e17"],
                analyticNarrative: "Yapay zekâ ne yalnızca edilgen bir araç ne de bağımsız bir faildir. İlişki, faydayı kabul eden fakat son sözü insanda tutmaya çalışan sürekli bir sınır pazarlığı olarak kurulmaktadır.",
                frameworkSummaries: [
                    "p0": "Hız ve fikir ortaklığını benimser; son kararın kendisinde olduğunu vurgular.",
                    "p1": "Pedagojik riski insan kontrolüyle sınırlar.",
                    "p2": "Diyalog içindeki sistemi yaratıcı ortak olarak konumlandırır.",
                    "p3": "Kullanımı metin kısaltma gibi dar araç işlevleriyle sınırlar.",
                    "p4": "Önerileri düşünsel uyarıcı kabul eder, veriyle yeniden denetler.",
                    "p5": "Sistemi ortak değil otomasyon aracı olarak tutar.",
                    "p6": "Yüksek riskli kararlarda kesin insan denetimi talep eder.",
                    "p7": "Seçenek sunmayı kabul eder, yön vermeyi reddeder."
                ], colorIndex: 0
            ),
            DebugCandidateTheme(
                id: "humanlike-distance", title: "Yakınlık ile analitik mesafe", stage: .candidate,
                centralConcept: "İnsansı cevaplar yakınlık yaratırken katılımcılar bunun gerçek bir zihin olmadığı bilgisini korumaya çalışıyor.",
                scope: "Anlama, niyet, zihin ve ilişki atıfları. Yalnızca arayüz kolaylığını anlatan ifadeler kapsam dışı.",
                codeIDs: ["mind", "dialogue"], evidenceIDs: ["e05", "e06", "e14", "e16"], contradictoryEvidenceIDs: ["e11"],
                analyticNarrative: "İnsansı dil basit bir benzetmeden fazlasını yaparak kullanım deneyimini yakınlaştırıyor; buna karşın katılımcılar eleştirel mesafeyi korumak için bu yakınlığı sık sık geri alıyor.",
                frameworkSummaries: [
                    "p0": "Ortaklık dili var, açık zihinsel atıf sınırlı.",
                    "p1": "İnsansı yakınlıktan çok pedagojik risk öne çıkıyor.",
                    "p2": "Niyeti anlayan bir zihin deneyimi güçlü.",
                    "p3": "Araç dili baskın; insansı atıf yok.",
                    "p4": "Diyalog düşünmeyi açıyor fakat zihin atfı yapılmıyor.",
                    "p5": "İnsansı yorumu açık biçimde reddediyor.",
                    "p6": "Anlayışlı cevap deneyimini analitik mesafeyle dengeliyor.",
                    "p7": "Soru-cevap düşünsel yakınlık üretiyor."
                ], colorIndex: 2
            ),
            DebugCandidateTheme(
                id: "trust-opacity", title: "Güven, denetim ve opaklık", stage: .final,
                centralConcept: "Güven, sistemin doğru görünmesinden değil çıktının insan tarafından izlenebilir ve düzeltilebilir olmasından doğuyor.",
                scope: "Kaynak belirsizliği, kara kutu, kontrol kaybı ve doğrulama pratikleri. Genel teknoloji kaygıları kapsam dışı.",
                codeIDs: ["blackbox", "threat", "doublecheck"], evidenceIDs: ["e03", "e04", "e08", "e10", "e12", "e13", "e15"], contradictoryEvidenceIDs: ["e18"],
                analyticNarrative: "Katılımcılar güveni sisteme ait sabit bir özellik olarak değil, kaynağa dönme ve çıktıyı sınama olanağı üzerinden kurmaktadır. Opaklık, özellikle kararın sonuçlarının yüksek olduğu bağlamlarda kontrol kaybı hissini büyütmektedir.",
                frameworkSummaries: [
                    "p0": "Kontrol pratiği var; opaklık belirgin bir sorun olarak anlatılmıyor.",
                    "p1": "Kaynak belirsizliği kullanımı durduran temel eşik.",
                    "p2": "Yakınlık güçlü, güvenlik ve opaklık geri planda.",
                    "p3": "Akıcı dilin kaynağı görünmezleştirdiğini fark ediyor.",
                    "p4": "Her öneriyi veriyle yeniden karşılaştırarak güven kuruyor.",
                    "p5": "Teknik ölçekte izlenebilirlik kaybını risk görüyor; bazı sonuçlarda opaklığı kabul ediyor.",
                    "p6": "İnsan kararını korumayı etik sınır olarak kuruyor.",
                    "p7": "Yönlendirme arttığında rahatsızlık ve kontrol kaybı hissediyor."
                ], colorIndex: 4
            )
        ]

        let formatter = ISO8601DateFormatter()
        let journal = [
            DebugJournalEntry(id: "j1", date: formatter.date(from: "2026-08-03T09:30:00Z")!, phase: .familiarization, title: "Araç ve ortaklık dili birlikte", reflection: "İlk okumada katılımcıların aynı görüşme içinde hem araç hem ortaklık metaforuna geçtiğini fark ettim. Bu iki kodu birbirini dışlayan kategoriler gibi ele almamak gerekiyor.", decision: "Metafor geçişlerini koruyacak biçimde aynı alıntıya çoklu kodlamaya izin ver.", linkedThemeIDs: ["controlled-partnership"], linkedExcerptIDs: ["e01", "e02"]),
            DebugJournalEntry(id: "j2", date: formatter.date(from: "2026-08-07T13:15:00Z")!, phase: .coding, title: "Güvensizlik ile kara kutuyu ayırma", reflection: "Her güvensizlik ifadesi şeffaflıkla ilgili değil. Kara kutu kodu yalnız kaynak veya işleyiş görünmezliği açıkça anlatıldığında kullanılmalı.", decision: "Kod kitabına dahil/dışla ölçütü eklendi; genel kaygı ‘tehdit’ kodunda tutuldu.", linkedThemeIDs: ["trust-opacity"], linkedExcerptIDs: ["e04", "e08"]),
            DebugJournalEntry(id: "j3", date: formatter.date(from: "2026-08-12T10:00:00Z")!, phase: .themeDevelopment, title: "Kontrollü ortaklık aday teması", reflection: "Araç ve ortaklık kodlarını bir üst başlıkta toplamak bir konu özeti yaratıyor. Daha güçlü örüntü, fayda kabul edilirken karar yetkisinin pazarlık edilmesi olabilir.", decision: "Tema adı ‘Araçtan ortağa’ yerine ‘Kontrollü ortaklık’ olarak değiştirildi.", linkedThemeIDs: ["controlled-partnership"], linkedExcerptIDs: ["e03", "e09", "e13"]),
            DebugJournalEntry(id: "j4", date: formatter.date(from: "2026-08-17T15:40:00Z")!, phase: .review, title: "Karşıt örnek temayı sınırlandırıyor", reflection: "Ayşe’nin bazı önerileri kontrol etmeden kullandığını söylemesi, insan denetiminin her zaman korunmadığını gösteriyor.", decision: "Karşıt alıntıyı silme; tema anlatısında denetimin kırılgan bir ideal olduğunu belirt.", linkedThemeIDs: ["controlled-partnership"], linkedExcerptIDs: ["e17"]),
            DebugJournalEntry(id: "j5", date: formatter.date(from: "2026-08-22T11:20:00Z")!, phase: .reporting, title: "Frekans yerine analitik önem", reflection: "İnsansı zihin daha az katılımcıda görünse de ilişki biçiminin değişimini açıklamak açısından önemli. Yaygınlık sıralaması rapor yapısını belirlememeli.", decision: "Rapor temasını frekansa göre değil araştırma sorusuna katkısına göre sırala.", linkedThemeIDs: ["humanlike-distance"], linkedExcerptIDs: ["e06", "e14"])
        ]

        return DebugResearchDataset(
            participants: participants,
            codebook: codebook,
            excerpts: excerpts,
            candidateThemes: candidateThemes,
            journal: journal
        )
    }()
}
