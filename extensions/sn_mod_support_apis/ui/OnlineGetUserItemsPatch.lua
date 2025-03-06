local ego_OnlineGetUserItems = OnlineGetUserItems

-- For some reason, this function returns `nil` in certain cases, which causes a bunch of scripts to start breaking when the interact menu code is injected.
-- Inspection of uses of `OnlineGetUserItems` show that no code seems to check for a `nil` value so it's likely not important that it returns `nil`.
function  OnlineGetUserItems( ... )
	local values = {ego_OnlineGetUserItems(...)}
	values[1] = values[1] or {}
	return unpack(values)
end
