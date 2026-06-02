--!strict
local function createElement(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local object = instance :: any

	if props then
		for key, value in props do
			object[key] = value
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	return instance
end

return createElement
