import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import path from "node:path"

const PROVIDER = "opencode"
const STATUS_DIR = path.join(homedir(), ".opencode", "agent-status")
const sessionCache = new Map()
const assistantMessageIDs = new Set()
const messageText = new Map()

function now() {
  return Date.now()
}

function statusFile(sessionID) {
  return path.join(STATUS_DIR, `${sessionID}.json`)
}

async function ensureDir() {
  await mkdir(STATUS_DIR, { recursive: true })
}

async function readStatus(sessionID) {
  try {
    return JSON.parse(await readFile(statusFile(sessionID), "utf8"))
  } catch {
    return null
  }
}

async function writeStatus(sessionID, status) {
  await ensureDir()
  const file = statusFile(sessionID)
  const tmp = `${file}.${process.pid}.${Date.now()}.tmp`
  await writeFile(tmp, `${JSON.stringify(status, null, 2)}\n`, "utf8")
  await rename(tmp, file)
}

async function updateStatus(sessionID, update) {
  const meta = sessionCache.get(sessionID) ?? {}
  const existing = await readStatus(sessionID)
  const current = existing ?? {
    provider: PROVIDER,
    sessionId: sessionID,
    pid: process.pid,
    cwd: meta.cwd ?? null,
    agentType: meta.agentType ?? null,
    status: "working",
    lastMessage: null,
    lastToolUse: null,
    tty: process.env.TTY ?? null,
    cmuxWorkspace: null,
    cmuxSurface: null,
    cmuxSocketPath: null,
    parentSessionId: meta.parentSessionId ?? null,
    waitReason: null,
    toolFailure: null,
    taskCompletedAt: null,
    createdAt: meta.createdAt ?? now(),
    updatedAt: meta.updatedAt ?? now(),
    statusChangedAt: meta.createdAt ?? now(),
  }

  await writeStatus(sessionID, update({ ...current }))
}

function firstSentence(text) {
  const line = text.split("\n")[0]?.slice(0, 200) ?? ""
  const trimmed = line.replace(/\s+/g, " ").trim()
  if (!trimmed) return ""
  const match = trimmed.match(/^(.*?)([.?]|$)/)
  return (match?.[1] ?? trimmed).trim() || trimmed
}

function classifyWaitReason(text) {
  const head = text.split("\n").slice(0, 2).join("\n")
  const tail = text.slice(-500)
  if (/\b(done|all done|all set|complete|completed|finished|everything.s (set|ready|updated|in place)|changes applied)\b/i.test(head)) {
    return "done"
  }
  const plainTail = tail.replace(/[\*`_~]/g, "")
  if (/\?\s*$/i.test(plainTail)) {
    return "question"
  }
  if (/(shall I|should I|would you|do you want|want me to|ready to|like me to|proceed|go ahead|sound good|look right|make sense|let me know|what do you think|next question)\b/i.test(tail)) {
    return "question"
  }
  return "done"
}

function formatToolUse(tool, args) {
  if (!args || (typeof args === "object" && Object.keys(args).length === 0)) {
    return tool
  }
  const serialized = typeof args === "string" ? args : JSON.stringify(args)
  return `${tool}: ${serialized.slice(0, 80)}`
}

function permissionTool(input) {
  if (input.metadata?.tool) return String(input.metadata.tool)
  if (input.metadata?.command) return `Bash: ${String(input.metadata.command)}`
  return input.title || input.type || "Permission"
}

export const ClaudeBlobsPlugin = async () => {
  return {
    event: async ({ event }) => {
      switch (event.type) {
      case "session.created":
      case "session.updated": {
        const info = event.properties.info
        sessionCache.set(info.id, {
          cwd: info.directory,
          parentSessionId: info.parentID ?? null,
          createdAt: info.time.created,
          updatedAt: info.time.updated,
          agentType: null,
        })
        await updateStatus(info.id, (status) => ({
          ...status,
          provider: PROVIDER,
          cwd: info.directory,
          parentSessionId: info.parentID ?? null,
          createdAt: status.createdAt ?? info.time.created,
          updatedAt: info.time.updated,
        }))
        break
      }
      case "session.deleted": {
        const sessionID = event.properties.info.id
        await rm(statusFile(sessionID), { force: true })
        sessionCache.delete(sessionID)
        messageText.delete(sessionID)
        break
      }
      case "session.status": {
        const { sessionID, status } = event.properties
        if (status.type === "busy") {
          await updateStatus(sessionID, (current) => ({
            ...current,
            status: "working",
            waitReason: null,
            toolFailure: null,
            updatedAt: now(),
            statusChangedAt: current.status === "working" ? current.statusChangedAt : now(),
          }))
        } else if (status.type === "retry") {
          await updateStatus(sessionID, (current) => ({
            ...current,
            status: "waiting",
            lastMessage: firstSentence(status.message),
            waitReason: "question",
            updatedAt: now(),
            statusChangedAt: current.status === "waiting" ? current.statusChangedAt : now(),
          }))
        } else if (status.type === "idle") {
          const text = messageText.get(sessionID) ?? ""
          await updateStatus(sessionID, (current) => ({
            ...current,
            status: "waiting",
            lastMessage: firstSentence(text) || current.lastMessage,
            waitReason: classifyWaitReason(text),
            updatedAt: now(),
            statusChangedAt: current.status === "waiting" ? current.statusChangedAt : now(),
          }))
        }
        break
      }
      case "session.idle": {
        const sessionID = event.properties.sessionID
        const text = messageText.get(sessionID) ?? ""
        await updateStatus(sessionID, (current) => ({
          ...current,
          status: "waiting",
          lastMessage: firstSentence(text) || current.lastMessage,
          waitReason: classifyWaitReason(text),
          updatedAt: now(),
          statusChangedAt: current.status === "waiting" ? current.statusChangedAt : now(),
        }))
        break
      }
      case "session.error": {
        const sessionID = event.properties.sessionID
        if (!sessionID) break
        const message = event.properties.error?.data?.message ?? "OpenCode session error"
        await updateStatus(sessionID, (current) => ({
          ...current,
          status: "waiting",
          lastMessage: firstSentence(message),
          waitReason: "question",
          toolFailure: "error",
          updatedAt: now(),
          statusChangedAt: current.status === "waiting" ? current.statusChangedAt : now(),
        }))
        break
      }
      case "message.updated": {
        const info = event.properties.info
        if (info.role === "assistant") {
          assistantMessageIDs.add(info.id)
        }
        break
      }
      case "message.part.updated": {
        const { part } = event.properties
        if (!assistantMessageIDs.has(part.messageID)) break
        if (part.type === "text") {
          messageText.set(part.sessionID, part.text)
        }
        if (part.type === "tool" && part.state.status === "error") {
          await updateStatus(part.sessionID, (current) => ({
            ...current,
            status: "waiting",
            lastToolUse: part.tool,
            lastMessage: firstSentence(part.state.error),
            waitReason: "question",
            toolFailure: "error",
            updatedAt: now(),
            statusChangedAt: current.status === "waiting" ? current.statusChangedAt : now(),
          }))
        }
        if (part.type === "retry") {
          const retryMessage = part.error?.data?.message ?? "OpenCode retry"
          await updateStatus(part.sessionID, (current) => ({
            ...current,
            status: "waiting",
            lastMessage: firstSentence(retryMessage),
            waitReason: "question",
            updatedAt: now(),
            statusChangedAt: current.status === "waiting" ? current.statusChangedAt : now(),
          }))
        }
        break
      }
      default:
        break
      }
    },
    "chat.message": async (input) => {
      await updateStatus(input.sessionID, (current) => ({
        ...current,
        status: "working",
        lastMessage: null,
        waitReason: null,
        toolFailure: null,
        updatedAt: now(),
        statusChangedAt: current.status === "working" ? current.statusChangedAt : now(),
      }))
    },
    "permission.ask": async (input) => {
      await updateStatus(input.sessionID, (current) => ({
        ...current,
        status: "permission",
        lastToolUse: permissionTool(input),
        waitReason: null,
        updatedAt: now(),
        statusChangedAt: current.status === "permission" ? current.statusChangedAt : now(),
      }))
    },
    "tool.execute.before": async (input, output) => {
      await updateStatus(input.sessionID, (current) => ({
        ...current,
        status: "working",
        lastToolUse: formatToolUse(input.tool, input.args),
        waitReason: null,
        toolFailure: null,
        updatedAt: now(),
        statusChangedAt: current.status === "working" ? current.statusChangedAt : now(),
      }))
    },
    "tool.execute.after": async (input, output) => {
      await updateStatus(input.sessionID, (current) => ({
        ...current,
        status: "working",
        lastToolUse: formatToolUse(input.tool, input.args),
        taskCompletedAt: output.metadata?.taskCompletedAt ?? current.taskCompletedAt,
        updatedAt: now(),
        statusChangedAt: current.status === "working" ? current.statusChangedAt : now(),
      }))
    },
    "experimental.session.compacting": async (input) => {
      await updateStatus(input.sessionID, (current) => ({
        ...current,
        status: "compacting",
        updatedAt: now(),
        statusChangedAt: current.status === "compacting" ? current.statusChangedAt : now(),
      }))
    },
  }
}

export default ClaudeBlobsPlugin
