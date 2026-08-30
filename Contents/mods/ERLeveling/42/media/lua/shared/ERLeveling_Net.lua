--[[
    ERLeveling_Net.lua
    ------------------
    One code path for every mutation (PLAN.md 9, "Single-player: short-circuit the
    command round-trip ... so there is exactly one code path for the logic").

    Client  --request-->  [server handler]  --result-->  Client
    Single player: request() calls the handler inline and delivers the result
    synchronously. The handler never knows which it was.

    THE CLIENT NEVER WRITES RUNES OR STATS. It sends intent and renders whatever
    the authoritative reply says.
]]

ERNet = ERNet or {}
ERNet.handlers = ERNet.handlers or {}   -- command  -> function(player, args) -> replyTable
ERNet.results  = ERNet.results  or {}   -- command  -> function(args)

--- Register the server-side handler for a command.
function ERNet.handle(command, fn)
    ERNet.handlers[command] = fn
end

--- Register the client-side handler for a result.
function ERNet.onResult(command, fn)
    ERNet.results[command] = fn
end

--- True when this process owns the authoritative data.
function ERNet.isAuthority()
    -- Dedicated server, or single player (neither client nor server flags set).
    if isServer() then return true end
    if not isClient() then return true end
    return false
end

--- Run a command's handler locally. Server-side entry point.
function ERNet.dispatch(player, command, args)
    local fn = ERNet.handlers[command]
    if not fn then
        print("[ERLeveling] no handler for command '" .. tostring(command) .. "'")
        return nil
    end
    local ok, reply = pcall(fn, player, args or {})
    if not ok then
        ERCompat.throttledError("handler " .. tostring(command), reply)
        return { ok = false, reason = "internal_error" }
    end
    return reply
end

--- Deliver a result to the local client handler (single player, or the host's
-- own player in a listen server).
function ERNet.deliverLocal(command, args)
    local fn = ERNet.results[command]
    if not fn then return end
    ERCompat.guard("result " .. tostring(command), fn, args or {})
end

--- Client -> server. In single player this executes inline.
function ERNet.request(player, command, args)
    if isClient() then
        pcall(function()
            sendClientCommand(player, ERBalance.NET_MODULE, command, args or {})
        end)
        return
    end
    local reply = ERNet.dispatch(player, command, args or {})
    if reply ~= nil then
        ERNet.deliverLocal(command .. "Result", reply)
    end
end

--- Server -> one client. In single player this is a direct local delivery.
function ERNet.reply(player, command, args)
    if isServer() then
        pcall(function()
            sendServerCommand(player, ERBalance.NET_MODULE, command, args or {})
        end)
        return
    end
    ERNet.deliverLocal(command, args or {})
end

--- Server -> everyone.
function ERNet.broadcast(command, args)
    if isServer() then
        pcall(function()
            sendServerCommand(ERBalance.NET_MODULE, command, args or {})
        end)
        return
    end
    ERNet.deliverLocal(command, args or {})
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
-- Server side: accept client intents.
if isServer() then
    ERCompat.onEvent("OnClientCommand", function(module, command, player, args)
        if module ~= ERBalance.NET_MODULE then return end
        local reply = ERNet.dispatch(player, command, args or {})
        if reply ~= nil then
            ERNet.reply(player, command .. "Result", reply)
        end
    end)
end

-- Client side: accept authoritative results.
if isClient() then
    ERCompat.onEvent("OnServerCommand", function(module, command, args)
        if module ~= ERBalance.NET_MODULE then return end
        ERNet.deliverLocal(command, args or {})
    end)
end
