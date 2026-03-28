// SimpleScript Spring Web MVC
// Re-exports Jakarta Servlet types for Spring-style usage

import { HttpServletRequest, HttpServletResponse, createServletResponse } from "@/lib/jakarta/servlet"

// Convenience: create a fresh response
function newResponse(): HttpServletResponse {
    return createServletResponse()
}
