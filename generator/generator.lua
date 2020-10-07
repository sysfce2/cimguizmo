--------------------------------------------------------------------------
--script for auto_funcs.h and auto_funcs.cpp generation
--expects LuaJIT
--------------------------------------------------------------------------
assert(_VERSION=='Lua 5.1',"Must use LuaJIT")
assert(bit,"Must use LuaJIT")
local script_args = {...}
local COMPILER = script_args[1]

local CPRE,CTEST
if COMPILER == "gcc" or COMPILER == "clang" then
    CPRE = COMPILER..[[ -E -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_API="" -DIMGUI_IMPL_API="" ]]
    CTEST = COMPILER.." --version"
elseif COMPILER == "cl" then
    CPRE = COMPILER..[[ /E /DIMGUI_DISABLE_OBSOLETE_FUNCTIONS /DIMGUI_API="" /DIMGUI_IMPL_API="" ]]
    CTEST = COMPILER
else
    print("Working without compiler ")
	error("cant work with "..COMPILER.." compiler")
end
--test compiler present
local HAVE_COMPILER = false

local pipe,err = io.popen(CTEST,"r")
if pipe then
    local str = pipe:read"*a"
    print(str)
    pipe:close()
    if str=="" then
        HAVE_COMPILER = false
    else
        HAVE_COMPILER = true
    end
else
    HAVE_COMPILER = false
    print(err)
end
assert(HAVE_COMPILER,"gcc, clang or cl needed to run script")


print("HAVE_COMPILER",HAVE_COMPILER)

--------------------------------------------------------------------------
--this table has the functions to be skipped in generation
--------------------------------------------------------------------------
local cimgui_manuals = {
    -- igLogText = true,
    -- ImGuiTextBuffer_appendf = true,
}
--------------------------------------------------------------------------
--this table is a dictionary to force a naming of function overloading (instead of algorythmic generated)
--first level is cimguiname without postfix, second level is the signature of the function, value is the
--desired name
---------------------------------------------------------------------------
local cimgui_overloads = {
    --igPushID = {
        --["(const char*)"] =           "igPushIDStr",
        --["(const char*,const char*)"] = "igPushIDRange",
        --["(const void*)"] =           "igPushIDPtr",
        --["(int)"] =                   "igPushIDInt"
    --},
}

--------------------------header definitions
local cimgui_header = 
[[//This file is automatically generated by generator.lua from https://github.com/cimgui/cimguizmo
//based on ImGuizmo.h file version XXX from https://github.com/CedricGuillemet/ImGuizmo
]]
--------------------------------------------------------------------------
--helper functions
--------------------------------functions for C generation
--load parser module
package.path = package.path.."../../cimgui/generator/?.lua"
local cpp2ffi = require"cpp2ffi"
local read_data = cpp2ffi.read_data
local save_data = cpp2ffi.save_data
local copyfile = cpp2ffi.copyfile
local serializeTableF = cpp2ffi.serializeTableF

local func_header_generate = cpp2ffi.func_header_generate
local func_implementation = cpp2ffi.func_implementation


--generate cimgui.cpp cimgui.h 
local function cimgui_generation(parser,name)

    local hstrfile = read_data("./"..name.."_template.h")

	local outpre,outpost = parser.structs_and_enums[1], parser.structs_and_enums[2]

	local cstructsstr = outpre..outpost 

    hstrfile = hstrfile:gsub([[#include "imgui_structs%.h"]],cstructsstr)
    local cfuncsstr = func_header_generate(parser)
    hstrfile = hstrfile:gsub([[#include "auto_funcs%.h"]],cfuncsstr)
    save_data("./output/"..name..".h",cimgui_header,hstrfile)
    
    --merge it in cimplot_template.cpp to cimplot.cpp
    local cimplem = func_implementation(parser)

    local hstrfile = read_data("./"..name.."_template.cpp")

    hstrfile = hstrfile:gsub([[#include "auto_funcs%.cpp"]],cimplem)
    save_data("./output/"..name..".cpp",cimgui_header,hstrfile)

end
--------------------------------------------------------
-----------------------------do it----------------------
--------------------------------------------------------
--get implot.h version--------------------------
local pipe,err = io.open("../ImGuizmo/ImGuizmo.h","r")
if not pipe then
    error("could not open file:"..err)
end
local implot_version
while true do
    local line = pipe:read"*l"
    implot_version = line:match([[%s+v(.+)]])
    if implot_version then break end
end
pipe:close()
cimgui_header = cimgui_header:gsub("XXX",implot_version)
print("IMGUIZMO_VERSION",implot_version)


-------------funtion for parsing implot headers
local function parseImGuiHeader(header,names)
	--prepare parser
	local parser = cpp2ffi.Parser()
	parser.getCname = function(stname,funcname,namespace)
		--local pre = (stname == "") and "ImPlot_" or stname.."_"
		local pre = (stname == "") and (namespace and (namespace=="ImGui" and "ig" or namespace.."_") or "ig") or stname.."_"
		return pre..funcname
	end
	parser.cname_overloads = cimgui_overloads
	parser.manuals = cimgui_manuals
	parser.UDTs = {"ImVec2","ImVec4","ImColor","ImRect"}--,"ImPlotPoint","ImPlotLimits"}
	
	local include_cmd = COMPILER=="cl" and [[ /I ]] or [[ -I ]]
	local extra_includes = include_cmd.." ../../cimgui/imgui "
	
	parser:take_lines(CPRE..extra_includes..header, names, COMPILER)
	
	return parser
end
--generation
print("------------------generation with "..COMPILER.."------------------------")
local modulename = "cimguizmo"
local parser1 = parseImGuiHeader([[../ImGuizmo/ImGuizmo.h]],{[[ImGuizmo]]})
parser1:do_parse()

save_data("./output/overloads.txt",parser1.overloadstxt)
cimgui_generation(parser1,modulename)
save_data("./output/definitions.lua",serializeTableF(parser1.defsT))
local structs_and_enums_table = parser1:gen_structs_and_enums_table()
save_data("./output/structs_and_enums.lua",serializeTableF(structs_and_enums_table))
save_data("./output/typedefs_dict.lua",serializeTableF(parser1.typedefs_dict))

-------------------------------json saving
--avoid mixed tables (with string and integer keys)
local function json_prepare(defs)
    --delete signatures in function
    for k,def in pairs(defs) do
        for k2,v in pairs(def) do
            if type(k2)=="string" then
                def[k2] = nil
            end
        end
    end
    return defs
end
---[[
local json = require"json"
local json_opts = {dict_on_empty={defaults=true}}
save_data("./output/definitions.json",json.encode(json_prepare(parser1.defsT),json_opts))
save_data("./output/structs_and_enums.json",json.encode(structs_and_enums_table))
save_data("./output/typedefs_dict.json",json.encode(parser1.typedefs_dict))
--]]
-------------------copy C files to repo root
copyfile("./output/"..modulename..".h", "../"..modulename..".h")
copyfile("./output/"..modulename..".cpp", "../"..modulename..".cpp")
os.remove("./output/"..modulename..".h")
os.remove("./output/"..modulename..".cpp")
print"all done!!"
