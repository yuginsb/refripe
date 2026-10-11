import Foundation

/// Demo dataset converted from the HTML mockup (`app.js`: listings, sellers, chats, orders, notifs,
/// sellerStats, recommendations). Dates are relative to `now` so the demo always looks fresh.
struct DemoSeed {
    var profiles: [UUID: UserProfile]
    var preferences: [UUID: UserPreferences]
    var phones: [String: UUID]
    var listings: [Listing]
    var wishlists: [UUID: Set<UUID>]
    var threads: [OfferThread]
    var orders: [Order]
    var conversations: [DemoConversation]
    var messages: [UUID: [ChatMessage]]
    var notifications: [UUID: [AppNotification]]
    var stats: SellerStats
    var recommendations: [SellerRecommendation]

    static func make(now: Date = .now) -> DemoSeed {
        let cal = Calendar.current
        func ago(minutes: Double = 0, hours: Double = 0, days: Double = 0) -> Date {
            now.addingTimeInterval(-(minutes * 60 + hours * 3_600 + days * 86_400))
        }
        func monthsAgo(_ m: Int) -> Date { cal.date(byAdding: .month, value: -m, to: now) ?? now }
        /// Absolute day of the current year ("12 juil."), moved to last year if it would be in the future.
        func past(month: Int, day: Int, hour: Int = 14) -> Date {
            var c = cal.dateComponents([.year], from: now)
            c.month = month; c.day = day; c.hour = hour
            let d = cal.date(from: c) ?? now
            return d > now ? (cal.date(byAdding: .year, value: -1, to: d) ?? d) : d
        }
        /// "Hier" at a given hour.
        func yesterday(_ hour: Int, _ minute: Int = 0) -> Date {
            let y = cal.date(byAdding: .day, value: -1, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: y) ?? ago(days: 1)
        }

        // MARK: Profiles (mockup `sellers` + the buyer of order 1)
        func user(_ id: UUID, _ username: String, _ first: String, _ city: String, _ district: String,
                  verified: Bool, rating: Double, sales: Int, months: Int, response: Int?) -> UserProfile {
            UserProfile(id: id, username: username, firstName: first, city: city, district: district,
                        avatarURL: nil, verified: verified, rating: rating, salesCount: sales,
                        memberSince: monthsAgo(months), responseTimeMinutes: response)
        }
        let people = [
            user(DemoIDs.awa, "Awa_Style225", "Awa", "Abidjan", "Cocody", verified: true, rating: 4.8, sales: 127, months: 8, response: 10),
            user(DemoIDs.karim, "Karim_Fripe", "Karim", "Abidjan", "Plateau", verified: false, rating: 4.4, sales: 31, months: 2, response: 45),
            user(DemoIDs.sneak, "SneakDak", "Ibrahim", "Abidjan", "Yopougon", verified: true, rating: 4.9, sales: 340, months: 12, response: 15),
            user(DemoIDs.fatou, "Fatou_Elegance", "Fatou", "Dakar", "Plateau", verified: true, rating: 5.0, sales: 58, months: 5, response: 20),
            user(DemoIDs.second, "SecondLook.sn", "Ndèye", "Dakar", "Almadies", verified: true, rating: 4.7, sales: 212, months: 11, response: 30),
            user(DemoIDs.fatouK, "Fatou_K", "Fatou", "Abidjan", "Riviera", verified: false, rating: 4.6, sales: 3, months: 3, response: 60),
        ]
        let profiles = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })

        var awaPrefs = UserPreferences()
        awaPrefs.categories = [.femme]
        awaPrefs.brands = ["Nike", "Zara"]
        awaPrefs.isAdultConfirmed = true
        awaPrefs.onboardingCompleted = true
        awaPrefs.introGuideSeen = true
        awaPrefs.swipeCoachSeen = false
        awaPrefs.streakDays = 3
        awaPrefs.lastActiveDay = cal.startOfDay(for: ago(days: 1))   // bumped to 4 on launch ("Série de 4 jours")

        // MARK: Listings (mockup `listings`)
        func listing(_ n: Int, _ title: String, _ desc: String, price: FCFA, old: FCFA? = nil,
                     size: SizeType, _ sizeLabel: String, district: String, city: String, seller: UUID,
                     cond: ItemCondition, tags: [String], brand: String, color: String, views: Int,
                     lastPiece: Bool = false, negotiable: Bool, minOffer: FCFA? = nil, gender: Gender,
                     delivery: [DeliveryMethod], hoursAgo: Double) -> Listing {
            Listing(id: DemoIDs.listing(n), sellerId: seller, title: title, description: desc, price: price,
                    oldPrice: old, sizeType: size, sizeLabel: sizeLabel, gender: gender, condition: cond,
                    brand: brand, color: color, tags: tags, city: city, district: district,
                    photos: [ListingPhoto(assetName: "listing-\(n)")], defectComment: nil, views: views,
                    favoritesCount: max(3, views / 9), isLastPiece: lastPiece, negotiable: negotiable,
                    minOffer: negotiable ? minOffer : nil, deliveryMethods: delivery, status: .active,
                    createdAt: ago(hours: hoursAgo))
        }
        let listings: [Listing] = [
            listing(1, "Robe wax imprimé, motif Ankara",
                    "Robe en pagne wax authentique, coupe cintrée, portée 3 fois seulement. Fermeture éclair dos en bon état. Idéale pour une cérémonie ou une sortie.",
                    price: 4_500, size: .haut, "Taille M", district: "Cocody", city: "Abidjan", seller: DemoIDs.awa,
                    cond: .veryGood, tags: ["Wax", "Cérémonie", "Coton"], brand: "Wax local", color: "Multicolore", views: 132,
                    negotiable: true, minOffer: 3_500, gender: .femme, delivery: [.relais, .mainPropre], hoursAgo: 2),
            listing(2, "Chemise vintage à carreaux",
                    "Chemise en flanelle, léger bouloché sur une manche mais aucune tache. Parfaite pour un look décontracté.",
                    price: 2_000, size: .haut, "Taille L", district: "Plateau", city: "Abidjan", seller: DemoIDs.karim,
                    cond: .good, tags: ["Vintage", "Homme"], brand: "Vintage", color: "Bleu", views: 54,
                    negotiable: false, gender: .homme, delivery: [.mainPropre], hoursAgo: 5),
            listing(3, "Baskets Nike Air",
                    "Semelle encore marquée, quelques traces d'usure sur le talon, cuir nettoyé récemment.",
                    price: 8_000, size: .chaussures, "Pointure 42", district: "Yopougon", city: "Abidjan", seller: DemoIDs.sneak,
                    cond: .good, tags: ["Sport", "Nike"], brand: "Nike", color: "Blanc", views: 301, lastPiece: true,
                    negotiable: true, minOffer: 6_000, gender: .homme, delivery: [.relais, .mainPropre, .yango], hoursAgo: 9),
            listing(4, "Boubou traditionnel brodé",
                    "Boubou brodé main, porté une seule fois pour un mariage. Tissu bazin riche.",
                    price: 10_000, old: 12_000, size: .unique, "Taille unique", district: "Plateau", city: "Dakar", seller: DemoIDs.fatou,
                    cond: .excellent, tags: ["Bazin", "Mariage"], brand: "Bazin", color: "Blanc", views: 214,
                    negotiable: true, minOffer: 8_000, gender: .femme, delivery: [.relais, .yango], hoursAgo: 20),
            listing(5, "Jean mom fit taille haute",
                    "Denim épais, coupe mom fit tendance, taille haute confortable.",
                    price: 3_000, size: .pantalon, "Taille 38", district: "Marcory", city: "Abidjan", seller: DemoIDs.awa,
                    cond: .veryGood, tags: ["Denim", "Femme"], brand: "Sans marque précise", color: "Bleu", views: 76,
                    negotiable: false, gender: .femme, delivery: [.relais, .mainPropre], hoursAgo: 28),
            listing(6, "Sac à main cuir vintage",
                    "Cuir véritable, patine du temps qui donne du caractère, fermoir en bon état.",
                    price: 6_500, size: .unique, "Taille unique", district: "Almadies", city: "Dakar", seller: DemoIDs.second,
                    cond: .good, tags: ["Cuir", "Accessoire"], brand: "Vintage", color: "Marron", views: 98,
                    negotiable: true, minOffer: 5_000, gender: .femme, delivery: [.relais, .mainPropre, .yango], hoursAgo: 34),
            listing(7, "Robe en wax pour fille, 4 ans",
                    "Petite robe en pagne wax, portée pour deux baptêmes. Coupe évasée, confortable pour jouer. Aucune tache, couleurs encore vives.",
                    price: 2_500, size: .enfant, "4 ans", district: "Cocody", city: "Abidjan", seller: DemoIDs.awa,
                    cond: .veryGood, tags: ["Wax", "Fille"], brand: "Wax local", color: "Multicolore", views: 88,
                    negotiable: true, minOffer: 1_800, gender: .enfant, delivery: [.relais, .mainPropre], hoursAgo: 50),
            listing(8, "Ensemble t-shirt et short, 6 ans",
                    "Ensemble coton pour garçon. Le t-shirt a légèrement passé au lavage, le short est comme neuf. Idéal pour l'école.",
                    price: 1_500, size: .enfant, "6 ans", district: "Yopougon", city: "Abidjan", seller: DemoIDs.karim,
                    cond: .good, tags: ["Coton", "Garçon"], brand: "Sans marque précise", color: "Rouge", views: 41,
                    negotiable: false, gender: .enfant, delivery: [.mainPropre], hoursAgo: 74),
            listing(9, "Pyjama bébé et chaussons, 0-3 mois",
                    "Pyjama en coton doux porté trois semaines, mon bébé a grandi trop vite. Lavé et repassé, vendu avec les chaussons assortis.",
                    price: 2_000, size: .enfant, "0-3 mois", district: "Plateau", city: "Dakar", seller: DemoIDs.fatou,
                    cond: .excellent, tags: ["Coton", "Bébé"], brand: "Sans marque précise", color: "Jaune", views: 63,
                    negotiable: true, minOffer: 1_500, gender: .bebe, delivery: [.relais, .yango], hoursAgo: 100),
        ]

        // MARK: Offer threads
        let threads = [
            OfferThread(id: DemoIDs.offerBoubou, listingId: DemoIDs.listing(4), buyerId: DemoIDs.awa, sellerId: DemoIDs.fatou,
                        rounds: [OfferRound(by: .buyer, amount: 7_000, action: .offer, at: ago(minutes: 70)),
                                 OfferRound(by: .seller, amount: 8_500, action: .counter, at: ago(minutes: 30))],
                        status: .pending, updatedAt: ago(minutes: 30)),
            OfferThread(id: DemoIDs.offerRobeFille, listingId: DemoIDs.listing(7), buyerId: DemoIDs.karim, sellerId: DemoIDs.awa,
                        rounds: [OfferRound(by: .buyer, amount: 2_000, action: .offer, at: ago(hours: 3))],
                        status: .pending, updatedAt: ago(hours: 3)),
        ]

        // MARK: Orders (mockup `orders`; the mockup's buyer "Aïcha" is Awa here)
        func order(_ n: Int, listing l: Int, seller: UUID, buyer: UUID, buyerName: String, price: FCFA,
                   delivery: DeliveryMethod, payment: PaymentMethod, history: [(OrderStatus, Date)]) -> Order {
            let src = listings[l - 1]
            return Order(id: DemoIDs.order(n), listingId: src.id, listingTitle: src.title, listingPhoto: src.photos.first,
                         sellerId: seller, buyerId: buyer, buyerName: buyerName, itemPrice: price, deliveryFee: delivery.fee,
                         delivery: delivery, payment: payment, status: history.last?.0 ?? .paymentPending,
                         history: history.map { OrderEvent(status: $0.0, at: $0.1) }, createdAt: history.first?.1 ?? now)
        }
        let threeDays = ago(days: 3)
        let orders = [
            order(1, listing: 1, seller: DemoIDs.awa, buyer: DemoIDs.fatouK, buyerName: "Fatou K.", price: 4_500, delivery: .relais, payment: .wave,
                  history: [(.paymentPending, yesterday(18, 40)), (.paid, yesterday(18, 41)), (.awaitingShipment, yesterday(18, 41))]),
            order(2, listing: 5, seller: DemoIDs.awa, buyer: DemoIDs.karim, buyerName: "Karim D.", price: 3_000, delivery: .relais, payment: .orangeMoney,
                  history: [(.paymentPending, threeDays), (.paid, threeDays.addingTimeInterval(60)),
                            (.awaitingShipment, threeDays.addingTimeInterval(60)), (.shipped, ago(days: 2))]),
            order(3, listing: 4, seller: DemoIDs.fatou, buyer: DemoIDs.awa, buyerName: "Awa", price: 9_000, delivery: .yango, payment: .wave,
                  history: [(.paymentPending, yesterday(10)), (.paid, yesterday(10, 1)), (.awaitingShipment, yesterday(10, 1)),
                            (.shipped, yesterday(16)), (.delivered, ago(hours: 3)), (.buyerValidation, ago(hours: 3))]),
            order(4, listing: 3, seller: DemoIDs.sneak, buyer: DemoIDs.awa, buyerName: "Awa", price: 8_000, delivery: .relais, payment: .wave,
                  history: [(.paymentPending, past(month: 7, day: 12)), (.paid, past(month: 7, day: 12)), (.awaitingShipment, past(month: 7, day: 12)),
                            (.shipped, past(month: 7, day: 13)), (.delivered, past(month: 7, day: 14)), (.buyerValidation, past(month: 7, day: 14)),
                            (.completed, past(month: 7, day: 16))]),
            order(5, listing: 6, seller: DemoIDs.second, buyer: DemoIDs.awa, buyerName: "Awa", price: 6_500, delivery: .relais, payment: .orangeMoney,
                  history: [(.paymentPending, past(month: 6, day: 2)), (.paid, past(month: 6, day: 2)), (.awaitingShipment, past(month: 6, day: 2)),
                            (.shipped, past(month: 6, day: 3)), (.delivered, past(month: 6, day: 4)), (.buyerValidation, past(month: 6, day: 4)),
                            (.completed, past(month: 6, day: 5))]),
        ]

        // MARK: Conversations (mockup `chats.awa`: "me" = Awa, "them" = Fatou K.)
        let robeWax = DemoIDs.conversationRobeWax
        let robeLines: [(UUID, String, Date)] = [
            (DemoIDs.fatouK, "Bonjour, la robe wax est toujours dispo ?", yesterday(17, 2)),
            (DemoIDs.awa, "Oui toujours dispo", yesterday(17, 5)),
            (DemoIDs.fatouK, "Dernier prix ?", yesterday(17, 9)),
            (DemoIDs.awa, "4000 possible si vous récupérez à Cocody, sinon 4500 livrée", yesterday(17, 12)),
            (DemoIDs.fatouK, "Ok je prends en livraison", yesterday(18, 30)),
            (DemoIDs.awa, "Parfait, je valide la commande de mon côté", yesterday(18, 42)),
        ]
        let baskets = DemoIDs.conversationBaskets
        let basketLines: [(UUID, String, Date)] = [
            (DemoIDs.awa, "Salut ! Les Baskets Nike Air sont toujours disponibles en 42 ?", yesterday(20, 15)),
            (DemoIDs.sneak, "Oui toujours dispo. Je peux t'envoyer une photo de la semelle si tu veux.", yesterday(21, 3)),
        ]
        func msgs(_ conv: UUID, _ lines: [(UUID, String, Date)]) -> [ChatMessage] {
            lines.map { ChatMessage(id: UUID(), conversationId: conv, senderId: $0.0, text: $0.1, sentAt: $0.2) }
        }
        let conversations = [
            DemoConversation(id: robeWax, listingId: DemoIDs.listing(1), members: [DemoIDs.awa, DemoIDs.fatouK], unread: [:]),
            DemoConversation(id: baskets, listingId: DemoIDs.listing(3), members: [DemoIDs.awa, DemoIDs.sneak], unread: [DemoIDs.awa: 1]),
        ]
        let messages = [robeWax: msgs(robeWax, robeLines), baskets: msgs(baskets, basketLines)]

        // MARK: Notifications (mockup `notifs`, tutoiement)
        let notifs = [
            AppNotification(id: DemoIDs.notification(1), kind: .counterOffer, title: "Contre-offre reçue",
                            body: "Fatou_Elegance te propose \(Fmt.fcfa(8_500)) pour le Boubou brodé",
                            createdAt: ago(minutes: 30), read: false, listingId: DemoIDs.listing(4)),
            AppNotification(id: DemoIDs.notification(2), kind: .priceDrop, title: "Baisse de prix sur une envie",
                            body: "Boubou traditionnel brodé passe à \(Fmt.fcfa(10_000)) (-\(Fmt.number(2_000)))",
                            createdAt: ago(hours: 2), read: false, listingId: DemoIDs.listing(4)),
            AppNotification(id: DemoIDs.notification(3), kind: .newInSize, title: "Nouvel article dans ta taille",
                            body: "Une robe M vient d'être publiée à Cocody",
                            createdAt: ago(hours: 5), read: false),
            AppNotification(id: DemoIDs.notification(4), kind: .message, title: "Nouveau message",
                            body: "SneakDak t'a répondu", createdAt: yesterday(21, 3), read: false,
                            listingId: DemoIDs.listing(3), conversationId: baskets),
            AppNotification(id: DemoIDs.notification(5), kind: .streak, title: "Série de 4 jours",
                            body: "Continue à découvrir aujourd'hui pour garder ta série",
                            createdAt: yesterday(9), read: true),
        ]

        // MARK: Dashboard (mockup `sellerStats`, `recommendations`)
        let stats = SellerStats(sales: 4, salesDelta: "+1 vs mois dernier",
                                revenue: 75_000, revenueDelta: "+17 000 FCFA vs mois dernier",
                                views: 1_720, viewsDelta: "+19% vs mois dernier",
                                favorites: 120, favoritesDelta: "+24 vs mois dernier",
                                monthlyGoal: 100_000, tier: "Argent", nextTier: "Or",
                                tierSalesNow: 4, tierSalesNeeded: 7,
                                weekViews: [80, 140, 95, 210, 260, 190, 300])
        let recos = [
            SellerRecommendation(symbol: "chart.line.downtrend.xyaxis", title: "Baisse le prix du Boubou brodé",
                                 body: "214 vues mais aucune vente depuis 2 semaines. Une baisse à 9 000 FCFA le remettrait en avant dans les résultats de recherche.",
                                 cta: "Ajuster l'annonce", listingId: DemoIDs.listing(4)),
            SellerRecommendation(symbol: "camera", title: "Ajoute des photos à ta Chemise vintage",
                                 body: "Les annonces avec 4 photos ou plus se vendent en moyenne 2× plus vite sur ReFripe.",
                                 cta: "Compléter l'annonce", listingId: DemoIDs.listing(2)),
            SellerRecommendation(symbol: "megaphone", title: "Partage tes Baskets Nike Air",
                                 body: "C'est ton article le plus vu (301 vues) — un partage sur ton statut WhatsApp peut déclencher la vente cette semaine.",
                                 cta: "Voir l'annonce à partager", listingId: DemoIDs.listing(3)),
            SellerRecommendation(symbol: "bolt", title: "Continue à répondre aussi vite",
                                 body: "Ton temps de réponse moyen (~10 min) te place dans le top 5% des vendeuses de Cocody, ce qui améliore ta visibilité dans Découvrir.",
                                 cta: nil, listingId: nil),
        ]

        return DemoSeed(profiles: profiles,
                        preferences: [DemoIDs.awa: awaPrefs],
                        phones: [DemoIDs.awaPhone: DemoIDs.awa],
                        listings: listings,
                        wishlists: [DemoIDs.awa: [DemoIDs.listing(2), DemoIDs.listing(4)]],
                        threads: threads,
                        orders: orders,
                        conversations: conversations,
                        messages: messages,
                        notifications: [DemoIDs.awa: notifs],
                        stats: stats,
                        recommendations: recos)
    }
}

/// Internal conversation record (viewer-independent); projected to `Conversation` for the signed-in user.
struct DemoConversation: Hashable {
    let id: UUID
    var listingId: UUID?
    var members: [UUID]
    var unread: [UUID: Int]

    func other(than me: UUID) -> UUID { members.first { $0 != me } ?? me }
}
