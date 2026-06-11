-- Core/EventBus.lua - minimal synchronous publish/subscribe.
local _, ns = ...

local EventBus = { handlers = {} }
ns.EventBus = EventBus

-- Subscribe fn to a topic. fn receives the published payload.
function EventBus:Subscribe(topic, fn)
    local list = self.handlers[topic]
    if not list then
        list = {}
        self.handlers[topic] = list
    end
    list[#list + 1] = fn
end

-- Publish payload to every subscriber of topic, in subscription order.
function EventBus:Publish(topic, payload)
    local list = self.handlers[topic]
    if not list then return end
    for i = 1, #list do
        list[i](payload)
    end
end
