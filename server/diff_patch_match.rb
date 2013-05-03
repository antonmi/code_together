require 'uri'

#https://raw.github.com/nono/diff_match_patch-ruby/master/diff_match_patch.rb

module DMPTextEncode
  def encodeText(text)
    URI.encode(text, /[^0-9A-Za-z_.;!~*'(),\/?:@&=+$\#-]/)
  end

  def decodeText(text)
    URI.decode(text.force_encoding(Encoding::UTF_8))
  end
end

class DiffPatchMatch
  # Class representing one diff operation (delete, equal or insert)
  Diff = Struct.new(:op, :text)

  # Class representing one patch operation
  class Patch
    include DMPTextEncode

    attr_accessor :start1, :start2
    attr_accessor :length1, :length2
    attr_accessor :diffs

    # Constructor
    def initialize
      @start1 = @start2 = nil
      @length1 = @length2 = 0
      @diffs = []
    end

    # Emulate GNU diff's format
    # Header: @@ -382,8 +481,9 @@
    # Indices are printed as 1-based, not 0-based.
    def to_s
      if length1 == 0
        coords1 = start1.to_s + ",0"
      elsif length1 == 1
        coords1 = (start1 + 1).to_s
      else
        coords1 = (start1 + 1).to_s + "," + length1.to_s
      end
      if length2 == 0
        coords2 = start2.to_s + ",0"
      elsif length2 == 1
        coords2 = (start2 + 1).to_s
      else
        coords2 = (start2 + 1).to_s + "," + length2.to_s
      end
      text = '@@ -' + coords1 + ' +' + coords2 + " @@\n"
      # Encode the body of the patch with %xx notation.
      text += diffs.map do |diff|
        op = case diff.op
               when :insert; '+'
               when :delete; '-'
               when :equal ; ' '
             end
        op + encodeText(diff.text) + "\n"
      end.join.gsub('%20', ' ')
    end
  end

  include DMPTextEncode

  attr_accessor :diff_timeout
  attr_accessor :diff_editCost
  attr_accessor :match_threshold
  attr_accessor :match_distance
  attr_accessor :patch_deleteThreshold
  attr_accessor :patch_margin
  attr_reader :match_maxBits

  def initialize
    # Defaults.
    # Redefine these in your program to override the defaults.

    # Number of seconds to map a diff before giving up (0 for infinity).
    @diff_timeout = 1
    # Cost of an empty edit operation in terms of edit characters.
    @diff_editCost = 4
    # At what point is no match declared (0.0 = perfection, 1.0 = very loose).
    @match_threshold = 0.5
    # How far to search for a match (0 = exact location, 1000+ = broad match).
    # A match this many characters away from the expected location will add
    # 1.0 to the score (0.0 is a perfect match).
    @match_distance = 1000
    # When deleting a large block of text (over ~64 characters), how close does
    # the contents have to match the expected contents. (0.0 = perfection,
    # 1.0 = very loose).  Note that match_threshold controls how closely the
    # end points of a delete need to match.
    @patch_deleteThreshold = 0.5
    # Chunk size for context length.
    @patch_margin = 4

    @match_maxBits = 32
  end

  # Determine the common prefix of two strings.
  def diff_commonPrefix(text1, text2)
    # Quick check for common null cases.
    return 0  if text1.empty? || text2.empty? || text1[0] != text2[0]

    # Binary search.
    # Performance analysis: http://neil.fraser.name/news/2007/10/09/
    # See diff_patch_match_bench.rb
    pointer_min = 0
    pointer_max = [text1.length, text2.length].min
    pointer_mid = pointer_max
    pointer_start = 0
    while pointer_min < pointer_mid
      if text1[pointer_start...pointer_mid] ==
          text2[pointer_start...pointer_mid]
        pointer_min = pointer_mid
        pointer_start = pointer_min
      else
        pointer_max = pointer_mid
      end
      pointer_mid = (pointer_max - pointer_min) / 2 + pointer_min
    end

    pointer_mid
  end

  # Determine the common suffix of two strings.
  def diff_commonSuffix(text1, text2)
    # Quick check for common null cases.
    return 0  if text1.empty? || text2.empty? || text1[-1] != text2[-1]

    # Binary search.
    # Performance analysis: http://neil.fraser.name/news/2007/10/09/
    # See diff_patch_match_bench.rb
    pointer_min = 0
    pointer_max = [text1.length, text2.length].min
    pointer_mid = pointer_max
    pointer_end = 0
    while pointer_min < pointer_mid
      if text1[-pointer_mid..(-pointer_end-1)] ==
          text2[-pointer_mid..(-pointer_end-1)]
        pointer_min = pointer_mid
        pointer_end = pointer_min
      else
        pointer_max = pointer_mid
      end
      pointer_mid = (pointer_max - pointer_min) / 2 + pointer_min
    end

    pointer_mid
  end

  # Determine if the suffix of one string is the prefix of another.
  def diff_commonOverlap(text1, text2)
    # Cache the text lengths to prevent multiple calls.
    text1_length = text1.length
    text2_length = text2.length
    # Eliminate the null case.
    return 0  if text1_length.zero? || text2_length.zero?

    # Truncate the longer string.
    if text1_length > text2_length
      text1 = text1[-text2_length..-1]
    else
      text2 = text2[0...text1_length]
    end
    text_length = [text1_length, text2_length].min
    # Quick check for the whole case.
    return text_length if text1 == text2

    # Start by looking for a single character match
    # and increase length until no match is found.
    # Performance analysis: http://neil.fraser.name/news/2010/11/04/
    best, length = 0, 1
    loop do
      pattern = text1[(text_length - length)..-1]
      found = text2.index(pattern)
      return best  if found.nil?
      length += found
      if found == 0 || text1[(text_length - length)..-1] == text2[0..length]
        best = length
        length += 1
      end
    end
  end

  # Does a substring of shorttext exist within longtext such that the substring
  # is at least half the length of longtext?
  def diff_halfMatchI(longtext, shorttext, i)
    # Start with a 1/4 length Substring at position i as a seed.
    seed = longtext[i, longtext.length / 4]
    j = -1
    best_common = ''
    while j = shorttext.index(seed, j + 1)
      prefix_length = diff_commonPrefix(longtext[i..-1], shorttext[j..-1])
      suffix_length = diff_commonSuffix(longtext[0...i], shorttext[0...j])
      if best_common.length < suffix_length + prefix_length
        best_common = shorttext[(j - suffix_length)...j] +
            shorttext[j...(j + prefix_length)]
        best_longtext_a = longtext[0...(i - suffix_length)]
        best_longtext_b = longtext[(i + prefix_length)..-1]
        best_shorttext_a = shorttext[0...(j - suffix_length)]
        best_shorttext_b = shorttext[(j + prefix_length)..-1]
      end
    end
    if best_common.length * 2 >= longtext.length
      [best_longtext_a, best_longtext_b, best_shorttext_a, best_shorttext_b,
       best_common]
    end
  end

  # Do the two texts share a substring which is at least half the length of the
  # longer text?
  # This speedup can produce non-minimal diffs.
  def diff_halfMatch(text1, text2)
    # Don't risk returning a non-optimal diff if we have unlimited time
    return nil if diff_timeout <= 0

    shorttext, longtext = [text1, text2].sort_by(&:length)
    if longtext.length < 4 || shorttext.length * 2 < longtext.length
      return nil # Pointless.
    end

    # First check if the second quarter is the seed for a half-match.
    hm1 = diff_halfMatchI(longtext, shorttext, (longtext.length / 4.0).ceil)
    # Check again based on the third quarter.
    hm2 = diff_halfMatchI(longtext, shorttext, (longtext.length / 2.0).ceil)

    if hm1.nil? && hm2.nil?
      return nil
    elsif hm2.nil?
      hm = hm1
    elsif hm1.nil?
      hm = hm2
    else
      # Both matched.  Select the longest.
      hm = hm1[4].length > hm2[4].length ? hm1 : hm2
    end

    # A half-match was found, sort out the return data.
    if text1.length > text2.length
      text1_a, text1_b, text2_a, text2_b = hm
    else
      text2_a, text2_b, text1_a, text1_b = hm
    end
    mid_common = hm[4]

    [text1_a, text1_b, text2_a, text2_b, mid_common]
  end

  # Split two texts into an array of strings.  Reduce the texts to a string of
  # hashes where each Unicode character represents one line.
  def diff_linesToChars(text1, text2)
    line_array = ['']  # e.g. line_array[4] == "Hello\n"
    line_hash = {}     # e.g. line_hash["Hello\n"] == 4

    [text1, text2].map do |text|
      # Split text into an array of strings.  Reduce the text to a string of
      # hashes where each Unicode character represents one line.
      chars = ''
      text.each_line do |line|
        if line_hash[line]
          chars += line_hash[line].chr(Encoding::UTF_8)
        else
          chars += line_array.length.chr(Encoding::UTF_8)
          line_hash[line] = line_array.length
          line_array.push(line)
        end
      end
      chars
    end.push(line_array)
  end

  # Rehydrate the text in a diff from a string of line hashes to real lines of
  # text.
  def diff_charsToLines(diffs, line_array)
    diffs.each do |diff|
      diff.text = diff.text.chars.map{ |c| line_array[c.ord] }.join
    end
  end

  # Reorder and merge like edit sections.  Merge equalities.
  # Any edit section can move as long as it doesn't cross an equality.
  def diff_cleanupMerge(diffs)
    diffs.push(Diff.new(:equal, '')) # Add a dummy entry at the end.
    pointer = 0
    count_delete = count_insert = 0
    text_delete, text_insert = '', ''
    while pointer < diffs.length
      case diffs[pointer].op
        when :insert
          count_insert += 1
          text_insert += diffs[pointer].text
          pointer += 1
        when :delete
          count_delete += 1
          text_delete += diffs[pointer].text
          pointer += 1
        when :equal
          # Upon reaching an equality, check for prior redundancies.
          if count_delete + count_insert > 1
            if count_delete != 0 && count_insert != 0
              # Factor out any common prefixies.
              common_length = diff_commonPrefix(text_insert, text_delete)
              if common_length != 0
                if (pointer - count_delete - count_insert) > 0 &&
                    diffs[pointer - count_delete - count_insert - 1].op == :equal
                  diffs[pointer - count_delete - count_insert - 1].text +=
                      text_insert[0...common_length]
                else
                  diffs.unshift(Diff.new(:equal, text_insert[0...common_length]))
                  pointer += 1
                end
                text_insert = text_insert[common_length..-1]
                text_delete = text_delete[common_length..-1]
              end
              # Factor out any common suffixies.
              common_length = diff_commonSuffix(text_insert, text_delete)
              if common_length != 0
                diffs[pointer].text = text_insert[-common_length..-1] +
                    diffs[pointer].text
                text_insert = text_insert[0...-common_length]
                text_delete = text_delete[0...-common_length]
              end
            end
            # Delete the offending records and add the merged ones.
            if count_delete.zero?
              diffs[
                  pointer - count_delete - count_insert,
                  count_delete + count_insert
              ] = [Diff.new(:insert, text_insert)]
            elsif count_insert.zero?
              diffs[
                  pointer - count_delete - count_insert,
                  count_delete + count_insert
              ] = [Diff.new(:delete, text_delete)]
            else
              diffs[
                  pointer - count_delete - count_insert,
                  count_delete + count_insert
              ] = [Diff.new(:delete, text_delete), Diff.new(:insert, text_insert)]
            end
            pointer = pointer - count_delete - count_insert +
                (count_delete.zero? ? 0 : 1) + (count_insert.zero? ? 0 : 1) + 1
          elsif pointer != 0 && diffs[pointer - 1].op == :equal
            # Merge this equality with the previous one.
            diffs[pointer - 1].text += diffs[pointer].text
            diffs[pointer, 1] = []
          else
            pointer += 1
          end
          count_insert = count_delete = 0
          text_delete, text_insert = '', ''
      end # case
    end # while

    if diffs.last.text.empty?
      diffs.pop # Remove the dummy entry at the end.
    end

    # Second pass: look for single edits surrounded on both sides by equalities
    # which can be shifted sideways to eliminate an equality.
    # e.g: A<ins>BA</ins>C -> <ins>AB</ins>AC
    changes = false
    pointer = 1
    # Intentionally ignore the first and last element (don't need checking).
    while pointer < diffs.length - 1
      if diffs[pointer - 1].op == :equal && diffs[pointer + 1].op == :equal
        # This is a single edit surrounded by equalities.
        if diffs[pointer].text[-diffs[pointer - 1].text.length..-1] ==
            diffs[pointer - 1].text
          # Shift the edit over the previous equality.
          diffs[pointer].text = diffs[pointer - 1].text +
              diffs[pointer].text[0...-diffs[pointer - 1].text.length]
          diffs[pointer + 1].text = diffs[pointer - 1].text +
              diffs[pointer + 1].text
          diffs[pointer - 1, 1] = []
          changes = true
        elsif diffs[pointer].text[0...diffs[pointer + 1].text.length] ==
            diffs[pointer + 1].text
          # Shift the edit over the next equality.
          diffs[pointer - 1].text += diffs[pointer + 1].text
          diffs[pointer].text =
              diffs[pointer].text[diffs[pointer + 1].text.length..-1] +
                  diffs[pointer + 1].text
          diffs[pointer + 1, 1] = []
          changes = true
        end
      end
      pointer += 1
    end # while

    # If shifts were made, the diff needs reordering and another shift sweep.
    if changes
      diff_cleanupMerge(diffs)
    end
  end

  # Given two strings, compute a score representing whether the internal
  # boundary falls on logical boundaries.
  # Scores range from 5 (best) to 0 (worst).
  def diff_cleanupSemanticScore(one, two)
    if one.empty? || two.empty?
      # Edges are the best
      return 5
    end

    # Define some regex patterns for matching boundaries.
    punctuation = /[^a-zA-Z0-9]/
    whitespace = /\s/
    linebreak = /[\r\n]/
    blanklineEnd = /\n\r?\n$/
    blanklineStart = /^\r?\n\r?\n/

    # Each port of this function behaves slightly differently due to
    # subtle differences in each language's definition of things like
    # 'whitespace'.  Since this function's purpose is largely cosmetic,
    # the choice has been made to use each language's native features
    # rather than force total conformity.
    score = 0
    # One point for non-alphanumeric.
    if one[-1] =~ punctuation || two[0] =~ punctuation
      score += 1
      # Two points for whitespace.
      if one[-1] =~ whitespace || two[0] =~ whitespace
        score += 1
        # Three points for line breaks.
        if one[-1] =~ linebreak || two[0] =~ linebreak
          score += 1
          # Four points for blank lines.
          if one =~ blanklineEnd || two =~ blanklineStart
            score += 1
          end
        end
      end
    end

    score
  end

  # Look for single edits surrounded on both sides by equalities
  # which can be shifted sideways to align the edit to a word boundary.
  # e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
  def diff_cleanupSemanticLossless(diffs)
    pointer = 1
    # Intentionally ignore the first and last element (don't need checking).
    while pointer < diffs.length - 1
      if diffs[pointer - 1].op == :equal && diffs[pointer + 1].op == :equal
        # This is a single edit surrounded by equalities.
        equality1 = diffs[pointer - 1].text
        edit      = diffs[pointer].text
        equality2 = diffs[pointer + 1].text

        # First, shift the edit as far left as possible.
        common_offset = diff_commonSuffix(equality1, edit)
        if common_offset != 0
          common_string = edit[-common_offset..-1]
          equality1 = equality1[0...-common_offset]
          edit = common_string + edit[0...-common_offset]
          equality2 = common_string + equality2
        end

        # Second, step character by character right, looking for the best fit.
        bestEquality1 = equality1
        bestEdit = edit
        bestEquality2 = equality2
        bestScore = diff_cleanupSemanticScore(equality1, edit) +
            diff_cleanupSemanticScore(edit, equality2)
        while edit[0] == equality2[0]
          equality1 += edit[0]
          edit = edit[1..-1] + equality2[0]
          equality2 = equality2[1..-1]
          score = diff_cleanupSemanticScore(equality1, edit) +
              diff_cleanupSemanticScore(edit, equality2)
          # The >= encourages trailing rather than leading whitespace on edits.
          if score >= bestScore
            bestScore = score
            bestEquality1 = equality1
            bestEdit = edit
            bestEquality2 = equality2
          end
        end

        if diffs[pointer - 1].text != bestEquality1
          # We have an improvement, save it back to the diff.
          if bestEquality1.empty?
            diffs[pointer - 1, 1] = []
            pointer -= 1
          else
            diffs[pointer - 1].text = bestEquality1
          end
          diffs[pointer].text = bestEdit
          if bestEquality2.empty?
            diffs[pointer + 1, 1] = []
            pointer -= 1
          else
            diffs[pointer + 1].text = bestEquality2
          end
        end
      end
      pointer += 1
    end
  end

  # Reduce the number of edits by eliminating semantically trivial equalities.
  def diff_cleanupSemantic(diffs)
    changes = false
    equalities = []  # Stack of indices where equalities are found.
    last_equality = nil # Always equal to equalities.last[1]
    pointer = 0 # Index of current position.
                     # Number of characters that changed prior to the equality.
    length_insertions1 = length_deletions1 = 0
                     # Number of characters that changed after the equality.
    length_insertions2 = length_deletions2 = 0

    while pointer < diffs.length
      if diffs[pointer].op == :equal # Equality found.
        equalities.push(pointer)
        length_insertions1 = length_insertions2
        length_deletions1 = length_deletions2
        length_insertions2 = length_deletions2 = 0
        last_equality = diffs[pointer].text
      else  # An insertion or deletion.
        if diffs[pointer].op == :insert
          length_insertions2 += diffs[pointer].text.length
        else
          length_deletions2 += diffs[pointer].text.length
        end

        if last_equality &&
            last_equality.length <= [length_insertions1, length_deletions1].max &&
            last_equality.length <= [length_insertions2, length_deletions2].max
          # Duplicate record.
          diffs[equalities.last, 0] = [Diff.new(:delete, last_equality)]
          # Change second copy to insert.
          diffs[equalities.last + 1].op = :insert
          # Throw away the equality we just deleted.
          equalities.pop
          # Throw away the previous equality (it needs to be reevaluated).
          equalities.pop
          pointer = equalities.last || -1
          length_insertions1 = length_deletions1 = 0  # Reset the counters.
          length_insertions2 = length_deletions2 = 0
          last_equality = nil
          changes = true
        end
      end
      pointer += 1
    end

    # Normalize the diff.
    if changes
      diff_cleanupMerge(diffs)
    end
    diff_cleanupSemanticLossless(diffs)

    # Find any overlaps between deletions and insertions.
    # e.g: <del>abcxx</del><ins>xxdef</ins>
    #   -> <del>abc</del>xx<ins>def</ins>
    pointer = 1
    while pointer < diffs.length
      if diffs[pointer - 1].op == :delete && diffs[pointer].op == :insert
        deletion = diffs[pointer - 1].text
        insertion = diffs[pointer].text
        overlap_length = diff_commonOverlap(deletion, insertion)
        if overlap_length != 0
          # Overlap found.  Insert an equality and trim the surrounding edits.
          diffs[pointer, 0] = [Diff.new(:equal, insertion[0...overlap_length])]
          diffs[pointer - 1].text = deletion[0...-overlap_length]
          diffs[pointer + 1].text = insertion[overlap_length..-1]
          pointer += 1
        end
        pointer += 1
      end
      pointer += 1
    end
  end

  # Reduce the number of edits by eliminating operationally trivial equalities.
  def diff_cleanupEfficiency(diffs)
    changes = false
    equalities = []  # Stack of indices where equalities are found.
    last_equality = ''  # Always equal to equalities.last[1]
    pointer = 0  # Index of current position.
                     # Is there an insertion operation before the last equality.
    pre_ins = false
                     # Is there a deletion operation before the last equality.
    pre_del = false
                     # Is there an insertion operation after the last equality.
    post_ins = false
                     # Is there a deletion operation after the last equality.
    post_del = false
    while pointer < diffs.length
      if diffs[pointer].op == :equal # Equality found.
        if diffs[pointer].text.length < diff_editCost && (post_ins || post_del)
          # Candidate found.
          equalities.push(pointer)
          pre_ins = post_ins
          pre_del = post_del
          last_equality = diffs[pointer].text
        else
          # Not a candidate, and can never become one.
          equalities.clear
          last_equality = ''
        end
        post_ins = post_del = false
      else # An insertion or deletion.
        if diffs[pointer].op == :delete
          post_del = true
        else
          post_ins = true
        end
        # Five types to be split:
        # <ins>A</ins><del>B</del>XY<ins>C</ins><del>D</del>
        # <ins>A</ins>X<ins>C</ins><del>D</del>
        # <ins>A</ins><del>B</del>X<ins>C</ins>
        # <ins>A</del>X<ins>C</ins><del>D</del>
        # <ins>A</ins><del>B</del>X<del>C</del>
        #/
        if !last_equality.empty? &&
            ((pre_ins && pre_del && post_ins && post_del) ||
                ((last_equality.length < diff_editCost / 2) &&
                    [pre_ins, pre_del, post_ins, post_del].count(true) == 3))
          # Duplicate record.
          diffs[equalities.last, 0] = [Diff.new(:delete, last_equality)]
          # Change second copy to insert.
          diffs[equalities.last + 1].op = :insert
          equalities.pop # Throw away the equality we just deleted
          last_equality = ''
          if pre_ins && pre_del
            # No changes made which could affect previous entry, keep going.
            post_ins = post_del = true
            equalities.clear
          else
            equalities.pop  # Throw away the previous equality.
            pointer = equalities.last || -1
            post_ins = post_del = false
          end
          changes = true
        end
      end
      pointer += 1
    end

    if changes
      diff_cleanupMerge(diffs)
    end
  end

  # Convert a diff array into a pretty HTML report.
  def diff_prettyHtml(diffs)
    diffs.map do |diff|
      text = diff.text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').
          gsub('\n', '&para;<br>')
      case diff.op
        when :insert
          "<ins style=\"background:#e6ffe6;\">#{text}</ins>"
        when :delete
          "<del style=\"background:#ffe6e6;\">#{text}</del>"
        when :equal
          "<span>#{text}</span>"
      end
    end.join
  end

  # Compute and return the source text (all equalities and deletions).
  #
  def diff_text1(diffs)
    diffs.map do |diff|
      if diff.op == :insert
        ''
      else
        diff.text
      end
    end.join
  end

  # Compute and return the destination text (all equalities and insertions).
  def diff_text2(diffs)
    diffs.map do |diff|
      if diff.op == :delete
        ''
      else
        diff.text
      end
    end.join
  end

  # Crush the diff into an encoded string which describes the operations
  # required to transform text1 into text2.
  # E.g. =3\t-2\t+ing  -> Keep 3 chars, delete 2 chars, insert 'ing'.
  # Operations are tab-separated.  Inserted text is escaped using %xx notation.
  def diff_toDelta(diffs)
    diffs.map do |diff|
      case diff.op
        when :insert
          '+' + encodeText(diff.text)
        when :delete
          '-' + diff.text.length.to_s
        when :equal
          '=' + diff.text.length.to_s
      end
    end.join("\t").gsub('%20', ' ')
  end

  # Given the original text1, and an encoded string which describes the
  # operations required to transform text1 into text2, compute the full diff.
  def diff_fromDelta(text1, delta)
    diffs = []
    pointer = 0 # Cursor in text1
    delta.split("\t").each do |token|
      # Each token begins with a one character parameter which specifies the
      # operation of this token (delete, insert, equality).
      param = token[1..-1]
      case token[0]
        when '+'
          diffs.push(Diff.new(:insert, decodeText(param)))
        when '-', '='
          begin
            n = Integer(param)
            raise if n < 0
            text = text1[pointer...(pointer += n)]
            if token[0] == '='
              diffs.push(Diff.new(:equal, text))
            else
              diffs.push(Diff.new(:delete, text))
            end
          rescue ArgumentError => e
            raise ArgumentError.new(
                      "Invalid number in diff_fromDelta: #{param.inspect}")
          end
        else
          # Blank tokens are ok (from a trailing \t).
          # Anything else is an error.
          if !token.empty?
            raise ArgumentError.new(
                      "Invalid diff operation in diff_fromDelta: #{token.inspect}")
          end
      end
    end
    if pointer != text1.length
      raise ArgumentError.new("Delta length (#{pointer}) does not equal " +
                                  "source text length #{text1.length}")
    end
    diffs
  end

  # loc is a location in text1, compute and return the equivalent location in
  # text2.
  # e.g. 'The cat' vs 'The big cat', 1->1, 5->8
  def diff_xIndex(diffs, loc)
    chars1 = chars2 = 0
    last_chars1 = last_chars2 = 0
    x = diffs.index do |diff|
      if diff.op != :insert # Equality or deletion.
        chars1 += diff.text.length
      end
      if diff.op != :delete # Equality or insertion.
        chars2 += diff.text.length
      end
      if chars1 > loc # Overshot the location.
        true
      else
        last_chars1 = chars1
        last_chars2 = chars2
        false
      end
    end
    # Was the location deleted?
    if x && diffs[x].op == :delete
      last_chars2
    else
      # Add the remaining character length.
      last_chars2 + (loc - last_chars1)
    end
  end

  def diff_levenshtein(diffs)
    levenshtein = insertions = deletions = 0
    diffs.each do |diff|
      case diff.op
        when :insert
          insertions += diff.text.length
        when :delete
          deletions += diff.text.length
        when :equal
          # A deletion and an insertion is one substitution.
          levenshtein += [insertions, deletions].max
          insertions = deletions = 0
      end
    end

    levenshtein + [insertions, deletions].max
  end

  # Find the 'middle snake' of a diff, split the problem in two
  # and return the recursively constructed diff.
  # See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
  def diff_bisect(text1, text2, deadline)
    # Cache the text lengths to prevent multiple calls.
    text1_length = text1.length
    text2_length = text2.length
    max_d = (text1_length + text2_length + 1) / 2
    v_offset = max_d
    v_length = 2 * max_d
    v1 = Array.new(v_length, -1)
    v2 = Array.new(v_length, -1)
    v1[v_offset + 1] = 0
    v2[v_offset + 1] = 0
    delta = text1_length - text2_length

    # If the total number of characters is odd, then the front path will collide
    # with the reverse path.
    front = (delta % 2 != 0)
    # Offsets for start and end of k loop.
    # Prevents mapping of space beyond the grid.
    k1start = 0
    k1end = 0
    k2start = 0
    k2end = 0
    max_d.times do |d|
      # Bail out if deadline is reached.
      if deadline && Time.now >= deadline
        break
      end

      # Walk the front path one step.
      (-d + k1start).step(d - k1end, 2) do |k1|
        k1_offset = v_offset + k1
        if k1 == -d || k1 != d && v1[k1_offset - 1] < v1[k1_offset + 1]
          x1 = v1[k1_offset + 1]
        else
          x1 = v1[k1_offset - 1] + 1
        end
        y1 = x1 - k1
        while x1 < text1_length && y1 < text2_length && text1[x1] == text2[y1]
          x1 += 1
          y1 += 1
        end
        v1[k1_offset] = x1
        if x1 > text1_length
          # Ran off the right of the graph.
          k1end += 2
        elsif y1 > text2_length
          # Ran off the bottom of the graph.
          k1start += 2
        elsif front
          k2_offset = v_offset + delta - k1
          if k2_offset >= 0 && k2_offset < v_length && v2[k2_offset] != -1
            # Mirror x2 onto top-left coordinate system.
            x2 = text1_length - v2[k2_offset]
            if x1 >= x2
              # Overlap detected.
              return diff_bisectSplit(text1, text2, x1, y1, deadline)
            end
          end
        end
      end

      # Walk the reverse path one step.
      (-d + k2start).step(d - k2end, 2) do |k2|
        k2_offset = v_offset + k2
        if k2 == -d || k2 != d && v2[k2_offset - 1] < v2[k2_offset + 1]
          x2 = v2[k2_offset + 1]
        else
          x2 = v2[k2_offset - 1] + 1
        end
        y2 = x2 - k2
        while x2 < text1_length && y2 < text2_length && text1[-x2-1] == text2[-y2-1]
          x2 += 1
          y2 += 1
        end
        v2[k2_offset] = x2
        if x2 > text1_length
          # Ran off the left of the graph.
          k2end += 2
        elsif y2 > text2_length
          # Ran off the top of the graph.
          k2start += 2
        elsif !front
          k1_offset = v_offset + delta - k2
          if k1_offset >= 0 && k1_offset < v_length && v1[k1_offset] != -1
            x1 = v1[k1_offset]
            y1 = v_offset + x1 - k1_offset
            # Mirror x2 onto top-left coordinate system.
            x2 = text1_length - x2
            if x1 >= x2
              # Overlap detected.
              return diff_bisectSplit(text1, text2, x1, y1, deadline)
            end
          end
        end
      end
    end

    # Diff took too long and hit the deadline or
    # number of diffs equals number of characters, no commonality at all.
    [Diff.new(:delete, text1), Diff.new(:insert, text2)]
  end

  # Given the location of the 'middle snake', split the diff in two parts
  # and recurse.
  def diff_bisectSplit(text1, text2, x, y, deadline)
    text1a = text1[0...x]
    text2a = text2[0...y]
    text1b = text1[x..-1]
    text2b = text2[y..-1]

    # Compute both diffs serially.
    diffs = diff_main(text1a, text2a, false, deadline)
    diffsb = diff_main(text1b, text2b, false, deadline)

    diffs + diffsb
  end

  # Find the differences between two texts.  Simplifies the problem by stripping
  # any common prefix or suffix off the texts before diffing.
  def diff_main(text1, text2, checklines=nil, deadline=nil)
    # Set a deadline by which time the diff must be complete.
    if deadline.nil? && diff_timeout > 0
      deadline = Time.now + diff_timeout
    end

    # Check for null inputs.
    if text1.nil? || text2.nil?
      raise ArgumentError.new('Null input. (diff_main)')
    end

    # Check for equality (speedup).
    if text1 == text2
      if text1.empty?
        return []
      else
        return [Diff.new(:equal, text1)]
      end
    end

    # Default to checklines == true
    if checklines.nil?
      checklines = true
    end

    # Trim off common prefix (speedup).
    common_length = diff_commonPrefix(text1, text2)
    if common_length.nonzero?
      common_prefix = text1[0...common_length]
      text1 = text1[common_length..-1]
      text2 = text2[common_length..-1]
    end

    # Trim off common suffix (speedup).
    common_length = diff_commonSuffix(text1, text2)
    if common_length.nonzero?
      common_suffix = text1[-common_length..-1]
      text1 = text1[0...-common_length]
      text2 = text2[0...-common_length]
    end

    # Compute the diff on the middle block.
    diffs = diff_compute(text1, text2, checklines, deadline)

    # Restore the prefix and suffix.
    if common_prefix
      diffs.unshift(Diff.new(:equal, common_prefix))
    end
    if common_suffix
      diffs.push(Diff.new(:equal, common_suffix))
    end
    diff_cleanupMerge(diffs)

    diffs
  end

  # Find the differences between two texts.  Assumes that the texts do not
  # have any common prefix or suffix.
  def diff_compute(text1, text2, checklines, deadline)
    if text1.empty?
      # Just add some text (speedup).
      return [Diff.new(:insert, text2)]
    end

    if text2.empty?
      # Just delete some text (speedup).
      return [Diff.new(:delete, text1)]
    end

    shorttext, longtext = [text1, text2].sort_by(&:length)
    if i = longtext.index(shorttext)
      # Shorter text is inside the longer text (speedup).
      diffs = [Diff.new(:insert, longtext[0...i]),
               Diff.new(:equal, shorttext),
               Diff.new(:insert, longtext[(i + shorttext.length)..-1])]
      # Swap insertions for deletions if diff is reversed.
      if text1.length > text2.length
        diffs[0].op = diffs[2].op = :delete
      end
      return diffs
    end

    if shorttext.length == 1
      # Single character string.
      # After the previous speedup, the character can't be an equality.
      return [Diff.new(:delete, text1), Diff.new(:insert, text2)]
    end
    longtext = shorttext = nil  # Garbage collect.

    # Check to see if the problem can be split in two.
    if hm = diff_halfMatch(text1, text2)
      # A half-match was found, sort out the return data.
      text1_a, text1_b, text2_a, text2_b, mid_common = hm
      # Send both pairs off for separate processing.
      diffs_a = diff_main(text1_a, text2_a, checklines, deadline)
      diffs_b = diff_main(text1_b, text2_b, checklines, deadline)
      # Merge the results.
      return diffs_a + [Diff.new(:equal, mid_common)] + diffs_b
    end

    if checklines && text1.length > 100 && text2.length > 100
      return diff_lineMode(text1, text2, deadline)
    end

    return diff_bisect(text1, text2, deadline)
  end

  # Do a quick line-level diff on both strings, then rediff the parts for
  # greater accuracy.
  # This speedup can produce non-minimal diffs.
  def diff_lineMode(text1, text2, deadline)
    # Scan the text on a line-by-line basis first.
    text1, text2, line_array = diff_linesToChars(text1, text2)
    diffs = diff_bisect(text1, text2, deadline)

    # Convert the diff back to original text.
    diff_charsToLines(diffs, line_array)
    # Eliminate freak matches (e.g. blank lines)
    diff_cleanupSemantic(diffs)

    # Rediff any replacement blocks, this time character-by-character.
    # Add a dummy entry at the end.
    diffs.push(Diff.new(:equal, ''))
    pointer = 0
    count_delete = count_insert = 0
    text_delete = ''
    text_insert = ''
    while pointer < diffs.length
      case diffs[pointer].op
        when :insert
          count_insert += 1
          text_insert += diffs[pointer].text
        when :delete
          count_delete += 1
          text_delete += diffs[pointer].text
        when :equal
          # Upon reaching an equality, check for prior redundancies.
          if count_delete >= 1 && count_insert >= 1
            # Delete the offending records and add the merged ones.
            a = diff_main(text_delete, text_insert, false, deadline)
            diffs[pointer - count_delete - count_insert,
                  count_delete + count_insert] = []
            pointer = pointer - count_delete - count_insert
            diffs[pointer, 0] = a
            pointer = pointer + a.length
          end
          count_insert = count_delete = 0
          text_delete = ''
          text_insert = ''
      end
      pointer += 1
    end
    diffs.pop # Remove the dummy entry at the end.

    return diffs
  end

  # Initialise the alphabet for the Bitap algorithm.
  def match_alphabet(pattern)
    s = {}
    pattern.chars.each_with_index do |c, i|
      s[c] ||= 0
      s[c] |= 1 << (pattern.length - i - 1)
    end
    s
  end

  # Locate the best instance of 'pattern' in 'text' near 'loc' using the
  # Bitap algorithm.
  def match_bitap(text, pattern, loc)
    if pattern.length > match_maxBits
      throw ArgumentError.new("Pattern too long")
    end

    # Initialise the alphabet.
    s = match_alphabet(pattern)

    # Compute and return the score for a match with e errors and x location.
    match_bitapScore = -> e, x do
      accuracy = e.to_f / pattern.length
      proximity = (loc - x).abs
      if match_distance == 0
        # Dodge divide by zero error.
        return proximity == 0 ? accuracy : 1.0
      end
      return accuracy + (proximity.to_f / match_distance)
    end

    # Highest score beyond which we give up.
    score_threshold = match_threshold
    # Is there a nearby exact match? (speedup)
    best_loc = text.index(pattern, loc)
    if best_loc
      score_threshold = [match_bitapScore[0, best_loc], score_threshold].min
      # What about in the other direction? (speedup)
      best_loc = text.rindex(pattern, loc + pattern.length)
      if best_loc
        score_threshold = [match_bitapScore[0, best_loc], score_threshold].min
      end
    end

    # Initialise the bit arrays.
    match_mask = 1 << (pattern.length - 1)
    best_loc = nil

    last_rd = nil

    bin_max = pattern.length + text.length
    pattern.length.times do |d|
      # Scan for the best match; each iteration allows for one more error.
      # Run a binary search to determine how far from 'loc' we can stray at this
      # error level.
      bin_min = 0
      bin_mid = bin_max
      while bin_min < bin_mid
        if match_bitapScore[d, loc + bin_mid] <= score_threshold
          bin_min = bin_mid
        else
          bin_max = bin_mid
        end
        bin_mid = (bin_max - bin_min) / 2 + bin_min
      end
      # Use the result from this iteration as the maximum for the next.
      bin_max = bin_mid
      start = [1, loc - bin_mid + 1].max
      finish = [loc + bin_mid, text.length].min + pattern.length

      rd = Array.new(finish + 2, 0)
      rd[finish + 1] = (1 << d) - 1
      finish.downto(start) do |j|
        char_match = s[text[j - 1]] || 0
        if d == 0 # First pass: exact match.
          rd[j] = ((rd[j + 1] << 1) | 1) & char_match
        else # Subsequent passes: fuzzy match.
          rd[j] = ((rd[j + 1] << 1) | 1) & char_match |
              (((last_rd[j + 1] | last_rd[j]) << 1) | 1) | last_rd[j + 1]
        end
        if (rd[j] & match_mask).nonzero?
          score = match_bitapScore[d, j - 1]
          # This match will almost certainly be better than any existing match.
          # But check anyway.
          if score <= score_threshold
            # Told you so.
            score_threshold = score
            best_loc = j - 1
            if best_loc > loc
              # When passing loc, don't exceed our current distance from loc.
              start = [1, 2 * loc - best_loc].max
            else
              # Already passed loc, downhill from here on in.
              break
            end
          end
        end
      end
      # No hope for a (better) match at greater error levels.
      if match_bitapScore[d + 1, loc] > score_threshold
        break
      end
      last_rd = rd
    end

    best_loc
  end

  # Locate the best instance of 'pattern' in 'text' near 'loc'.
  def match_main(text, pattern, loc)
    # Check for null inputs.
    if [text, pattern, loc].any?(&:nil?)
      raise ArgumentError.new("Null input. (match_main)")
    end

    loc = [0, [loc, text.length].min].max
    if text == pattern
      # Shortcut (potentially not guaranteed by the algorithm)
      0
    elsif text.empty?
      # Nothing to match
      nil
    elsif text[loc, pattern.length] == pattern
      # Perfect match at the perfect spot!  (Includes case of null pattern)
      loc
    else
      # Do a fuzzy compare.
      match_bitap(text, pattern, loc)
    end
  end

  # Parse a textual representation of patches and return a list of patch
  # objects.
  def patch_fromText(textline)
    return []  if textline.empty?

    patches = []
    text = textline.split("\n")
    text_pointer = 0
    patch_header = /^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@$/
    while text_pointer < text.length
      m = text[text_pointer].match(patch_header)
      if m.nil?
        raise ArgumentError.new("Invalid patch string: #{text[text_pointer]}")
      end
      patch = Patch.new
      patches.push(patch)
      patch.start1 = m[1].to_i
      if m[2].empty?
        patch.start1 -= 1
        patch.length1 = 1
      elsif m[2] == '0'
        patch.length1 = 0
      else
        patch.start1 -= 1
        patch.length1 = m[2].to_i
      end

      patch.start2 = m[3].to_i
      if m[4].empty?
        patch.start2 -= 1
        patch.length2 = 1
      elsif m[4] == '0'
        patch.length2 = 0
      else
        patch.start2 -= 1
        patch.length2 = m[4].to_i
      end
      text_pointer += 1

      while text_pointer < text.length
        if text[text_pointer].empty?
          # Blank line? Whatever.
          text_pointer += 1
          next
        end

        sign = text[text_pointer][0]
        line = decodeText(text[text_pointer][1..-1])
        case sign
          when '-'
            # Deletion.
            patch.diffs.push(Diff.new(:delete, line))
          when '+'
            # Insertion.
            patch.diffs.push(Diff.new(:insert, line))
          when ' '
            # Minor equality
            patch.diffs.push(Diff.new(:equal, line))
          when '@'
            # Start of next patch.
            break
          else
            # WTF?
            raise ArgumentError.new("Invalid patch mode \"#{sign}\" in: #{line}")
        end
        text_pointer += 1
      end
    end

    patches
  end

  # Take a list of patches and return a textual representation.
  def patch_toText(patches)
    patches.join
  end

  # Increase the context until it is unique,
  # but don't let the pattern expand beyond match_maxBits
  def patch_addContext(patch, text)
    return  if text.empty?
    pattern = text[patch.start2, patch.length1]
    padding = 0

    # Look for the first and last matches of pattern in text.  If two different
    # matches are found, increase the pattern length.
    while text.index(pattern) != text.rindex(pattern) &&
        pattern.length < match_maxBits - 2*patch_margin
      padding += patch_margin
      pattern = text[[0, patch.start2 - padding].max...
                         (patch.start2 + patch.length1 + padding)]
    end
    # Add one chunk for good luck.
    padding += patch_margin

    # Add the prefix.
    prefix = text[[0, patch.start2 - padding].max...patch.start2]
    unless prefix.to_s.empty?
      patch.diffs.unshift(Diff.new(:equal, prefix))
    end
    # Add the suffix.
    suffix = text[patch.start2 + patch.length1, padding]
    unless suffix.to_s.empty?
      patch.diffs.push(Diff.new(:equal, suffix))
    end

    # Roll back the start points.
    patch.start1 -= prefix.length
    patch.start2 -= prefix.length
    # Extend the lengths.
    patch.length1 += prefix.length + suffix.length
    patch.length2 += prefix.length + suffix.length
  end

  # Compute a list of patches to turn text1 into text2.
  # Use diffs if provided, otherwise compute it ourselves.
  # There are four ways to call this function, depending on what data is
  # available to the caller:
  # Method 1:
  # a = text1, b = text2
  # Method 2:
  # a = diffs
  # Method 3 (optimal):
  # a = text1, b = diffs
  # Method 4 (deprecated, use method 3):
  # a = text1, b = text2, c = diffs
  def patch_make(*args)
    text1 = diffs = nil
    if args.length == 2 && args[0].is_a?(String) && args[1].is_a?(String)
      # Method 1: text1, text2
      # Compute diffs from text1 and text2.
      text1, text2 = args
      diffs = diff_main(text1, text2, true)
      if diffs.length > 2
        diff_cleanupSemantic(diffs)
        diff_cleanupEfficiency(diffs)
      end
    elsif args.length == 1 && args[0].is_a?(Array)
      # Method 2: diffs
      # Compute text1 from diffs.
      diffs = args[0]
      text1 = diff_text1(diffs)
    elsif args.length == 2 && args[0].is_a?(String) && args[1].is_a?(Array)
      # Method 3: text1, diffs
      text1, diffs = args
    elsif args.length == 3 && args[0].is_a?(String) && args[1].is_a?(String) &&
        args[2].is_a?(Array)
      # Method 4: text1, text2, diffs
      # text2 is not used.
      text1, text2, diffs = args
    else
      raise ArgumentError.new('Unknown call format to patch_make.')
    end

    return []  if diffs.empty? # Get rid of the null case.

    patches = []
    patch = Patch.new
    char_count1 = 0 # Number of characters into the text1 string.
    char_count2 = 0 # Number of characters into the text2 string.
                               # Start with text1 (prepatch_text) and apply the diffs until we arrive at
                               # text2 (postpatch_text).  We recreate the patches one by one to determine
                               # context info.
    prepatch_text = text1
    postpatch_text = text1
    diffs.each_with_index do |diff, x|
      if patch.diffs.empty? && diff.op != :equal
        # A new patch starts here.
        patch.start1 = char_count1
        patch.start2 = char_count2
      end

      case diff.op
        when :insert
          patch.diffs.push(diff)
          patch.length2 += diff.text.length
          postpatch_text = postpatch_text[0...char_count2] + diff.text +
              postpatch_text[char_count2..-1]
        when :delete
          patch.length1 += diff.text.length
          patch.diffs.push(diff)
          postpatch_text = postpatch_text[0...char_count2] +
              postpatch_text[(char_count2 + diff.text.length)..-1]
        when :equal
          if diff.text.length <= 2 * patch_margin &&
              !patch.diffs.empty? && diffs.length != x + 1
            # Small equality inside a patch.
            patch.diffs.push(diff)
            patch.length1 += diff.text.length
            patch.length2 += diff.text.length
          elsif diff.text.length >= 2 * patch_margin
            # Time for a new patch.
            unless patch.diffs.empty?
              patch_addContext(patch, prepatch_text)
              patches.push(patch)
              patch = Patch.new
              # Unlike Unidiff, our patch lists have a rolling context.
              # http://code.google.com/p/google-diff-match-patch/wiki/Unidiff
              # Update prepatch text & pos to reflect the application of the
              # just completed patch.
              prepatch_text = postpatch_text
              char_count1 = char_count2
            end
          end
      end

      # Update the current character count.
      if diff.op != :insert
        char_count1 += diff.text.length
      end
      if diff.op != :delete
        char_count2 += diff.text.length
      end
    end
                               # Pick up the leftover patch if not empty.
    unless patch.diffs.empty?
      patch_addContext(patch, prepatch_text)
      patches.push(patch)
    end

    patches
  end

  # Look through the patches and break up any which are longer than the maximum
  # limit of the match algorithm.
  def patch_splitMax(patches)
    patch_size = match_maxBits
    x = 0
    while x < patches.length
      if patches[x].length1 > patch_size
        big_patch = patches[x]
        # Remove the big old patch
        patches[x, 1] = []
        x -= 1
        start1 = big_patch.start1
        start2 = big_patch.start2
        pre_context = ''
        while !big_patch.diffs.empty?
          # Create one of several smaller patches.
          patch = Patch.new
          empty = true
          patch.start1 = start1 - pre_context.length
          patch.start2 = start2 - pre_context.length
          unless pre_context.empty?
            patch.length1 = patch.length2 = pre_context.length
            patch.diffs.push(Diff.new(:equal, pre_context))
          end
          while !big_patch.diffs.empty? &&
              patch.length1 < patch_size - patch_margin
            diff = big_patch.diffs.first
            if diff.op == :insert
              # Insertions are harmless.
              patch.length2 += diff.text.length
              start2 += diff.text.length
              patch.diffs.push(big_patch.diffs.shift)
              empty = false
            elsif diff.op == :delete && patch.diffs.length == 1 &&
                patch.diffs.first.op == :equal &&
                diff.text.length > 2 * patch_size
              # This is a large deletion.  Let it pass in one chunk.
              patch.length1 += diff.text.length
              start1 += diff.text.length
              empty = false
              patch.diffs.push(big_patch.diffs.shift)
            else
              # Deletion or equality.  Only take as much as we can stomach.
              diff_text = diff.text[0, patch_size - patch.length1 - patch_margin]
              patch.length1 += diff_text.length
              start1 += diff_text.length
              if diff.op == :equal
                patch.length2 += diff_text.length
                start2 += diff_text.length
              else
                empty = false
              end
              patch.diffs.push(Diff.new(diff.op, diff_text))
              if diff_text == big_patch.diffs.first.text
                big_patch.diffs.shift
              else
                big_patch.diffs.first.text =
                    big_patch.diffs.first.text[diff_text.length..-1]
              end
            end
          end
          # Compute the head context for the next patch.
          pre_context = diff_text2(patch.diffs)[-patch_margin..-1] || ''
          # Append the end context for this patch.
          post_context = diff_text1(big_patch.diffs)[0...patch_margin] || ''
          unless post_context.empty?
            patch.length1 += post_context.length
            patch.length2 += post_context.length
            if !patch.diffs.empty? && patch.diffs.last.op == :equal
              patch.diffs.last.text += post_context
            else
              patch.diffs.push(Diff.new(:equal, post_context))
            end
          end
          if !empty
            x += 1
            patches[x, 0] = [patch]
          end
        end
      end
      x += 1
    end # while x < patches.length
  end

  # Add some padding on text start and end so that edges can match something.
  # Intended to be called only from within patch_apply.
  def patch_addPadding(patches)
    padding_length = patch_margin
    null_padding = (1..padding_length).map{ |x| x.chr(Encoding::UTF_8) }.join

    # Bump all the patches forward.
    patches.each do |patch|
      patch.start1 += padding_length
      patch.start2 += padding_length
    end

    # Add some padding on start of first diff.
    patch = patches.first
    diffs = patch.diffs
    if diffs.empty? || diffs.first.op != :equal
      # Add nullPadding equality.
      diffs.unshift(Diff.new(:equal, null_padding))
      patch.start1 -= padding_length  # Should be 0.
      patch.start2 -= padding_length  # Should be 0.
      patch.length1 += padding_length
      patch.length2 += padding_length
    elsif padding_length > diffs.first.text.length
      # Grow first equality.
      extra_length = padding_length - diffs.first.text.length
      diffs.first.text = null_padding[diffs.first.text.length..-1] +
          diffs.first.text
      patch.start1 -= extra_length
      patch.start2 -= extra_length
      patch.length1 += extra_length
      patch.length2 += extra_length
    end

    # Add some padding on end of last diff.
    patch = patches.last
    diffs = patch.diffs
    if diffs.empty? || diffs.last.op != :equal
      # Add nullPadding equality.
      diffs.push(Diff.new(:equal, null_padding))
      patch.length1 += padding_length
      patch.length2 += padding_length
    elsif padding_length > diffs.last.text.length
      # Grow last equality.
      extra_length = padding_length - diffs.last.text.length
      diffs.last.text += null_padding[0, extra_length]
      patch.length1 += extra_length
      patch.length2 += extra_length
    end

    null_padding
  end

  # Merge a set of patches onto the text.  Return a patched text, as well
  # as a list of true/false values indicating which patches were applied.
  def patch_apply(patches, text)
    return [text, []]  if patches.empty?

    # Deep copy the patches so that no changes are made to originals.
    patches = Marshal.load(Marshal.dump(patches))

    null_padding = patch_addPadding(patches)
    text = null_padding + text + null_padding

    patch_splitMax(patches)
    # delta keeps track of the offset between the expected and actual location
    # of the previous patch.  If there are patches expected at positions 10 and
    # 20, but the first patch was found at 12, delta is 2 and the second patch
    # has an effective expected position of 22.
    delta = 0
    results = []
    patches.each_with_index do |patch, x|
      expected_loc = patch.start2 + delta
      text1 = diff_text1(patch.diffs)
      start_loc = end_loc = nil
      if text1.length > match_maxBits
        # patch_splitMax will only provide an oversized pattern in the case of
        # a monster delete.
        start_loc = match_main(text, text1[0, match_maxBits], expected_loc)
        if start_loc
          end_loc = match_main(text,
                               text1[(text1.length - match_maxBits)..-1],
                               expected_loc + text1.length - match_maxBits)
          if end_loc.nil? || start_loc >= end_loc
            # Can't find valid trailing context.  Drop this patch.
            start_loc = nil
          end
        end
      else
        start_loc = match_main(text, text1, expected_loc)
      end
      if start_loc.nil?
        # No match found.  :(
        results[x] = false
        # Subtract the delta for this failed patch from subsequent patches.
        delta -= patch.length2 - patch.length1
      else
        # Found a match.  :)
        results[x] = true
        delta = start_loc - expected_loc
        text2 = nil
        if end_loc.nil?
          text2 = text[start_loc, text1.length]
        else
          text2 = text[start_loc...(end_loc + match_maxBits)]
        end
        if text1 == text2
          # Perfect match, just shove the replacement text in.
          text = text[0, start_loc] + diff_text2(patch.diffs) +
              text[(start_loc + text1.length)..-1]
        else
          # Imperfect match.  Run a diff to get a framework of equivalent
          # indices.
          diffs = diff_main(text1, text2, false)
          if text1.length > match_maxBits &&
              diff_levenshtein(diffs).to_f / text1.length >
                  patch_deleteThreshold
            # The end points match, but the content is unacceptably bad.
            results[x] = false
          else
            diff_cleanupSemanticLossless(diffs)
            index1 = 0
            index2 = nil
            patch.diffs.each do |mod|
              if mod.op != :equal
                index2 = diff_xIndex(diffs, index1)
              end
              if mod.op == :insert  # Insertion
                text = text[0, start_loc + index2] + mod.text +
                    text[(start_loc + index2)..-1]
              elsif mod.op == :delete  # Deletion
                text = text[0, start_loc + index2] +
                    text[(start_loc + diff_xIndex(diffs, index1 + mod.text.length))..-1]
              end
              if mod.op != :delete
                index1 += mod.text.length
              end
            end
          end
        end
      end
    end
    # Strip the padding off.
    text = text[null_padding.length...-null_padding.length]

    [text, results]
  end

end