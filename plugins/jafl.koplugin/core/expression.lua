local Expression = {}

function Expression.evaluate(text, resolve)
    text=tostring(text or "0"):gsub("%s+","")
    local at=1
    local expression,term,factor
    factor=function()
        local sign=1
        if text:sub(at,at)=="-" then sign=-1; at=at+1 elseif text:sub(at,at)=="+" then at=at+1 end
        local value
        if text:sub(at,at)=="(" then
            at=at+1; value=expression()
            assert(text:sub(at,at)==")","missing ')' in expression: "..text); at=at+1
        else
            local number=text:sub(at):match("^%d+")
            if number then value=tonumber(number); at=at+#number
            else
                local name=text:sub(at):match("^[%a][%w_]*")
                assert(name,"invalid expression near '"..text:sub(at).."'")
                value=assert(resolve(name),"unresolved identifier: "..name); at=at+#name
            end
        end
        return sign*value
    end
    term=function()
        local value=factor()
        while true do
            local op=text:sub(at,at); if op~="*" and op~="/" then break end
            at=at+1; local rhs=factor()
            if op=="*" then value=value*rhs else
                assert(rhs~=0,"division by zero"); local quotient=value/rhs
                value=quotient<0 and math.ceil(quotient) or math.floor(quotient)
            end
        end
        return value
    end
    expression=function()
        local value=term()
        while true do
            local op=text:sub(at,at); if op~="+" and op~="-" then break end
            at=at+1; local rhs=term(); value=op=="+" and value+rhs or value-rhs
        end
        return value
    end
    local value=expression(); assert(at>#text,"unexpected expression suffix: "..text:sub(at))
    return value
end

return Expression
