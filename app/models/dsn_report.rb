
class DsnReport
  def initialize(rcpt_to:, code:, diagnostic:)
    @rcpt_to = rcpt_to
    @code = code
    @diagnostic = diagnostic
  end

  def to_raw
    <<~REPORT
      Final-Recipient: rfc822; #{@rcpt_to}
      Action: failed
      Status: #{status}
      Diagnostic-Code: smtp; #{diagnostic_code}
    REPORT
  end

  private
    def status
      diagnostic_code[/\b5\.\d+\.\d+\b/] || "5.0.0"
    end

    def diagnostic_code
      if @code.to_s.empty? || diagnostic.start_with?(@code.to_s)
        diagnostic
      else
        "#{@code} #{diagnostic}"
      end
    end

    def diagnostic
      @diagnostic.to_s.gsub(/\s+/, " ").strip
    end
end
