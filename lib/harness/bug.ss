import { PROMPT } from "./hooks"

class Bug {
    name: string
    importance?: int
    urgency?: int
    round?: int
    certainty?: int
    detectedCb?: fn
    fixedCb?: fn

    function onDetected(f: fn) {
        this.detectedCb = f
    }

    function onFixed(f: fn) {
        this.fixedCb = f
    }

    function detected(importance: int, urgency: int) {
        this.importance = importance
        this.urgency = urgency
        if (this.detectedCb != 0) {
            this.detectedCb()
        }
    }

    function fixed(round: int, certainty: int) {
        this.round = round
        this.certainty = certainty
        if (this.fixedCb != 0) {
            this.fixedCb()
        }
    }
}
