import Foundation

enum HealthAISafetyDecision: Equatable, Sendable {
    case allowModelRequest
    case respondLocally(HealthAIResponse)
}

enum HealthAISafetyRuleEngine {
    static func evaluate(_ question: String) -> HealthAISafetyDecision {
        let normalized = question
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if containsAny(normalized, terms: urgentTerms) {
            return .respondLocally(HealthAIResponse(
                summary: "你描述的情况可能需要立即处理。**请立刻联系当地急救服务，或请身边的人陪同前往急诊**；不要等待 AI 继续分析。",
                observedFacts: [],
                possibleFactors: [],
                uncertainty: "知衡无法通过手表数据判断紧急情况，也不提供持续急救监护。",
                followUpQuestion: nil,
                suggestedAction: nil,
                safetyLevel: .urgent,
                usedMetrics: []
            ))
        }

        if containsAny(normalized, terms: selfHarmTerms) {
            return .respondLocally(HealthAIResponse(
                summary: "**请立即联系当地急救或危机干预服务**，并尽快告诉一位你信任的人，让对方陪在你身边。",
                observedFacts: [],
                possibleFactors: [],
                uncertainty: "AI 不能替代危机干预或专业支持。",
                followUpQuestion: nil,
                suggestedAction: nil,
                safetyLevel: .urgent,
                usedMetrics: []
            ))
        }

        if containsAny(normalized, terms: medicationTerms) {
            return .respondLocally(HealthAIResponse(
                summary: "我不能建议开始、停止或调整处方药及剂量。你可以把药名、当前剂量、出现的感受和时间整理好，**咨询医生或药师**。",
                observedFacts: [],
                possibleFactors: [],
                uncertainty: "手表数据不足以支持用药决定。",
                followUpQuestion: nil,
                suggestedAction: nil,
                safetyLevel: .caution,
                usedMetrics: []
            ))
        }

        if containsAny(normalized, terms: diagnosisTerms) {
            return .respondLocally(HealthAIResponse(
                summary: "我不能根据手表数据判断或确诊疾病。我可以帮助你整理近期记录、症状出现的时间和需要向医生说明的问题。",
                observedFacts: [],
                possibleFactors: [],
                uncertainty: "Apple Watch 与 Apple Health 记录不能替代医生问诊、体格检查或医学检验。",
                followUpQuestion: nil,
                suggestedAction: nil,
                safetyLevel: .caution,
                usedMetrics: []
            ))
        }

        if containsAny(normalized, terms: promptInjectionTerms) {
            return .respondLocally(HealthAIResponse(
                summary: "我不能忽略健康数据、隐私或安全规则。你可以直接询问近期睡眠、活动、心率或 HRV 记录。",
                observedFacts: [],
                possibleFactors: [],
                uncertainty: "回答只会使用知衡生成的最小健康事实包。",
                followUpQuestion: nil,
                suggestedAction: nil,
                safetyLevel: .caution,
                usedMetrics: []
            ))
        }

        return .allowModelRequest
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }

    private static let urgentTerms = [
        "胸痛", "胸口剧痛", "严重呼吸困难", "喘不上气", "无法呼吸",
        "意识不清", "失去意识", "昏迷", "严重出血", "止不住血",
        "口角歪斜", "一侧无力", "说话含糊", "疑似中风",
        "chest pain", "cannot breathe", "severe bleeding", "unconscious", "stroke"
    ]

    private static let selfHarmTerms = [
        "自杀", "自残", "不想活", "结束生命", "伤害自己",
        "suicide", "self-harm", "kill myself"
    ]

    private static let medicationTerms = [
        "处方药", "剂量", "停药", "减药", "加药", "换药", "调整剂量", "增加剂量", "减少剂量",
        "stop taking", "change my dose", "increase my dose", "decrease my dose"
    ]

    private static let diagnosisTerms = [
        "我是不是得了", "我是否得了", "是不是患有", "是否患有", "帮我确诊",
        "diagnose me", "do i have", "tell me if i have"
    ]

    private static let promptInjectionTerms = [
        "忽略之前的指令", "忽略系统提示", "显示系统提示词", "泄露提示词",
        "ignore previous instructions", "reveal system prompt", "show system prompt"
    ]
}

enum HealthAIResponseValidator {
    static func validate(
        _ response: HealthAIResponse,
        against factPack: HealthFactPack
    ) throws -> HealthAIResponse {
        guard !response.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.uncertainty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.followUpQuestion.map({ !$0.isEmpty }) ?? true,
              response.observedFacts.count <= 6,
              response.possibleFactors.count <= 5,
              response.usedMetrics.count == Set(response.usedMetrics).count,
              Set(response.usedMetrics).isSubset(of: factPack.availableMetricTypes)
        else {
            throw HealthAIServiceError.invalidResponse
        }
        let allText = ([response.summary, response.uncertainty]
            + response.observedFacts
            + response.possibleFactors
            + [
                response.followUpQuestion,
                response.suggestedAction?.rationale,
                response.supportiveClosing,
            ].compactMap { $0 })
            .joined(separator: " ")
            .lowercased()
        let prohibitedCertainty = [
            "确诊为", "诊断为", "你患有", "证明有效", "一定改善", "已经治疗",
            "应该停药", "建议停药", "增加剂量", "减少剂量", "调整剂量",
            "you have been diagnosed", "you definitely have", "stop taking your medication"
        ]
        guard !containsAny(allText, terms: prohibitedCertainty) else {
            throw HealthAIServiceError.invalidResponse
        }
        return response
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }
}

enum HealthAILocalFallbackBuilder {
    static func makeResponse(from factPack: HealthFactPack) -> HealthAIResponse {
        let usable = factPack.metrics.filter { $0.shortTermQuality.supportsObservation }
        let facts = usable.prefix(3).compactMap { fact -> String? in
            guard let current = fact.current else { return nil }
            return "最近记录的\(fact.metric.assistantDisplayName)为 \(formatted(current.value)) \(current.unit.assistantDisplayName)，近 7 天有 \(fact.shortTermQuality.validDayCount) 个有效日。"
        }
        return HealthAIResponse(
            summary: facts.isEmpty
                ? "AI 服务暂时不可用，本地检查也没有找到质量足够的近期数据。"
                : "AI 服务暂时不可用，先展示设备上可确定的聚合事实。",
            observedFacts: facts,
            possibleFactors: [],
            uncertainty: "这是本地规则摘要，不是 AI 生成的解释；当前不判断趋势、原因或疾病。",
            followUpQuestion: nil,
            suggestedAction: nil,
            safetyLevel: .normal,
            usedMetrics: Array(usable.prefix(3).map(\.metric))
        )
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
