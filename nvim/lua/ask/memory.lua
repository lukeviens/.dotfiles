-- Turn-by-turn conversational memory. Each completed turn is distilled exactly once, from its
-- own original text, and the result is appended, never rewritten -- never re-summarizes its
-- own prior output, the cause of rolling-summarization drift ("a photocopy of a photocopy").
--
-- Two stages. M.score_sentences: a cheap local filter ranking a turn's own sentences by
-- self-information against this conversation's running vocabulary -- the same "remove the
-- least-impactful pixels first" idea seam carving uses for images, applied to words. M.extract:
-- one call to the model (via ask/model -- this module never talks to a specific backend)
-- pulling real facts/phrases out of only the survivors, never the whole turn and never the
-- accumulated memory, so there's nothing for drift to compound on.
local M = {}
local model = require("ask.model")

-- per-session word-frequency tables: "how surprising is this word" is relative to what this
-- conversation has already said. In-memory only; not a persistence layer.
local corpora = {} -- session_id -> { counts = {word -> n}, total = n }

-- a brand-new session has no vocabulary history, so every word in its first turn would
-- otherwise tie at zero self-information and nothing would get filtered. Seeding with common
-- English function words lets turn one tell "the/is/fine" apart from "config.json" without
-- needing history to lean on first.
local STOPWORD_SEED = {
	"the", "a", "an", "is", "are", "was", "were", "be", "to", "of", "in", "on", "at", "for",
	"and", "or", "it", "this", "that", "with", "as", "by", "from", "but", "not", "have", "has",
	"had", "i", "you", "we", "they", "he", "she", "do", "does", "did", "will", "would", "can",
	"could", "should", "there", "what", "which", "who", "how", "so", "if", "then", "than",
	"also", "just", "very", "really", "thing", "things",
}
local SEED_COUNT, SEED_TOTAL = 20, 400

local function corpus_for(session_id)
	if not corpora[session_id] then
		local counts = {}
		for _, w in ipairs(STOPWORD_SEED) do counts[w] = SEED_COUNT end
		corpora[session_id] = { counts = counts, total = SEED_TOTAL }
	end
	return corpora[session_id]
end

local function tokenize(s)
	local words = {}
	for w in s:lower():gmatch("%w+") do words[#words + 1] = w end
	return words
end

-- Pulls fenced code blocks and bare file:line references out before the prose pipeline sees
-- them: sentence-splitting would mangle a multi-line code block, and both are unambiguously
-- worth keeping regardless of surprisal. Returns (code_refs, text with those spans removed).
local function extract_code_refs(text)
	local refs = {}
	local clean = text:gsub("```%w*\n(.-)```", function(block)
		refs[#refs + 1] = "```\n" .. block .. "```"
		return ""
	end)
	for ref in clean:gmatch("[%w_%-%./]+%.%a%a+:%d+") do
		refs[#refs + 1] = ref
	end
	return refs, clean
end

-- splits on lines first (a bullet or a paragraph), then on sentence-ending punctuation
-- within each one. A line with no closing punctuation gets one, so its tail still matches.
local function split_sentences(text)
	local sentences = {}
	for line in text:gmatch("[^\n]+") do
		line = vim.trim(line)
		if not line:find("[%.!?]$") then line = line .. "." end
		for s in (line .. " "):gmatch("(.-[%.!?])%s+") do
			s = vim.trim(s)
			if s ~= "" then sentences[#sentences + 1] = s end
		end
	end
	return sentences
end

-- lexical signals that are objectively information-dense regardless of how common their
-- words are: numbers, code-/path-looking tokens, quoted or backticked spans, camelCase.
local function structural_bonus(s)
	local bonus = 0
	if s:find("%d") then bonus = bonus + 1 end
	if s:find("[%w_]+%.[%w_]+") or s:find("/[%w_%.%-]+/") then bonus = bonus + 1 end
	if s:find("`[^`]+`") or s:find('"[^"]+"') then bonus = bonus + 1 end
	if s:find("%l%u") then bonus = bonus + 1 end
	return bonus
end

-- Stage 1. Scores each sentence by self-information against the running corpus
-- (-log2(freq/total) summed over its words -- a mean would rank "Ok." above "The port is
-- 8080.", since one rare word beats a rare word diluted by common ones), keeps this turn's top
-- half by rank -- self-relative, no fixed threshold, and ties can't let filler through. The
-- corpus updates after scoring: a turn is judged against what came before it, and every word
-- updates the corpus regardless of whether its sentence survives.
function M.score_sentences(session_id, text)
	local corpus = corpus_for(session_id)
	local sentences = split_sentences(text)
	if #sentences == 0 then return {} end

	local scores = {}
	for i, s in ipairs(sentences) do
		local words = tokenize(s)
		local info = 0
		for _, w in ipairs(words) do
			local freq = (corpus.counts[w] or 0) + 1 -- +1 smoothing: unseen is surprising, not infinite
			info = info - math.log(freq / (corpus.total + 1), 2)
		end
		scores[i] = info + structural_bonus(s)
	end

	for _, s in ipairs(sentences) do
		for _, w in ipairs(tokenize(s)) do
			corpus.counts[w] = (corpus.counts[w] or 0) + 1
			corpus.total = corpus.total + 1
		end
	end

	local ranked = {}
	for i in ipairs(sentences) do ranked[i] = i end
	table.sort(ranked, function(x, y) return scores[x] > scores[y] end)
	local keep = {}
	for r = 1, math.ceil(#ranked / 2) do keep[ranked[r]] = true end

	local kept = {}
	for i, s in ipairs(sentences) do
		if keep[i] then kept[#kept + 1] = s end
	end
	return kept
end

-- Stage 2. on_done(facts): a list of short strings, empty if nothing survived or nothing was
-- worth keeping. Delegates the actual call to ask/model's M.quick -- this module only ever
-- describes what to ask for, never how to reach the model.
function M.extract(candidates, on_done)
	if #candidates == 0 then
		on_done({})
		return
	end
	local prompt = "Extract the key facts, decisions, names, and commitments from the "
		.. "following as a short bullet list, one per line, no preamble. If genuinely "
		.. "nothing is worth remembering, reply with exactly: (nothing)\n\n"
		.. table.concat(candidates, "\n")
	model.quick(prompt, function(ok, body)
		if not ok then
			on_done({})
			return
		end
		local facts = {}
		for line in body:gmatch("[^\n]+") do
			line = vim.trim((line:gsub("^%s*[%-%*•]%s*", ""):gsub("^%d+[%.%)]%s*", "")))
			if line ~= "" and not line:find("^%(nothing%)") then facts[#facts + 1] = line end
		end
		on_done(facts)
	end)
end

local function store_dir()
	return vim.fn.stdpath("state") .. "/ask-memory"
end

local function store_path(session_id)
	return store_dir() .. "/" .. session_id .. ".jsonl"
end

-- Append-only by construction: writefile's "a" flag never touches an existing line.
-- code_refs come from extract_code_refs verbatim -- never through stage 1 or 2.
function M.append(session_id, facts, code_refs)
	code_refs = code_refs or {}
	if #facts == 0 and #code_refs == 0 then return end
	vim.fn.mkdir(store_dir(), "p")
	local line = vim.json.encode({ at = os.time(), facts = facts, code_refs = code_refs })
	vim.fn.writefile({ line }, store_path(session_id), "a")
end

function M.read(session_id)
	if not session_id then return {} end
	local path = store_path(session_id)
	if vim.uv.fs_stat(path) == nil then return {} end
	local records = {}
	for _, line in ipairs(vim.fn.readfile(path)) do
		local ok, obj = pcall(vim.json.decode, line)
		if ok then records[#records + 1] = obj end
	end
	return records
end

-- Folds everything distilled so far into the prompt a turn actually sends, as explicit
-- context -- additive to --resume's lossless native session, not a replacement: this store
-- covers what --resume cannot, a reopened thread with no live session left, not near-term
-- fidelity. No records, or no session_id, returns `text` unchanged. Each item once: the same
-- file:line comes back turn after turn, and repeating it only costs tokens.
function M.inject(session_id, text)
	local records = M.read(session_id)
	if #records == 0 then return text end
	local lines, seen = { "Known so far from this conversation:" }, {}
	local function add(item)
		if seen[item] then return end
		seen[item] = true
		lines[#lines + 1] = "- " .. item
	end
	for _, r in ipairs(records) do
		for _, f in ipairs(r.facts or {}) do add(f) end
		for _, c in ipairs(r.code_refs or {}) do add(c) end
	end
	vim.list_extend(lines, { "", "---", "", text })
	return table.concat(lines, "\n")
end

-- The full pipeline for one completed turn -- fire-and-forget. A failure here (claude -p
-- erroring, a malformed response) never surfaces: pure background enrichment.
function M.distill_turn(session_id, question, answer)
	local code_refs, clean_text = extract_code_refs(question .. "\n\n" .. answer)
	local candidates = M.score_sentences(session_id, clean_text)
	M.extract(candidates, function(facts)
		pcall(M.append, session_id, facts, code_refs)
	end)
end

return M
