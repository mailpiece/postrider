import { normalizeFilteredText } from "helpers/text_helpers"

export function filterMatches(text, potentialMatch) {
  return normalizeQuickFindText(text).includes(normalizeQuickFindText(potentialMatch))
}

// Where filterMatches finds the query, as [start, end) offsets into the text as written.
export function filterMatchRanges(text, potentialMatch) {
  const query = normalizeQuickFindText(potentialMatch)
  if (!query.trim()) return []

  const folded = joinDigits(foldWithOffsets(text))
  const normalized = folded.map(entry => entry.char).join("")
  const ranges = []

  for (let at = normalized.indexOf(query); at !== -1; at = normalized.indexOf(query, at + query.length)) {
    ranges.push([ folded[at].index, folded[at + query.length - 1].index + 1 ])
  }

  return ranges
}

function normalizeQuickFindText(string) {
  return normalizeFilteredText(string)
    .replace(/(\d)[-./\s]+(?=\d)/g, "$1") // Join digits split by separators, as in tax ids
}

// One entry per folded character, with its UTF-16 offset in the text, which is what Text#splitText counts.
function foldWithOffsets(text) {
  return text.split("").flatMap((char, index) => Array.from(normalizeFilteredText(char), folded => ({ char: folded, index })))
}

const SEPARATOR = /[-./\s]/
const DIGIT = /\d/

// The same joining as normalizeQuickFindText, keeping where each kept character came from.
function joinDigits(entries) {
  const joined = []

  for (let start = 0; start < entries.length; start++) {
    if (SEPARATOR.test(entries[start].char)) {
      let end = start
      while (end < entries.length && SEPARATOR.test(entries[end].char)) end++

      if (!(DIGIT.test(entries[start - 1]?.char ?? "") && DIGIT.test(entries[end]?.char ?? ""))) {
        joined.push(...entries.slice(start, end))
      }
      start = end - 1
    } else {
      joined.push(entries[start])
    }
  }

  return joined
}
