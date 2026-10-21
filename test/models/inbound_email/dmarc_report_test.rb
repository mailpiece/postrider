require "test_helper"
require "base64"

class InboundEmail::DmarcReportTest < ActiveSupport::TestCase
  test "parses the DMARC aggregate report attached to mail sent to the dmarc-reports address" do
    email = create_inbound_email(rcpt_to: "dmarc-reports@example.com", raw: raw_with_report(AGGREGATE_XML))
    email.extract_attachments

    report = email.dmarc_report

    assert_equal "google.com", report.organization
    assert_equal "14054835605949254452", report.report_id
    assert_equal "example.com", report.policy.domain
    assert_equal "reject", report.policy.p
    assert_equal 1, report.records.size
    assert_equal "203.0.113.9", report.records.first.source_ip
    assert_equal "pass", report.records.first.dkim
  end

  test "is nil for mail that did not arrive at the dmarc-reports address" do
    email = create_inbound_email(rcpt_to: "list@example.com", raw: raw_with_report(AGGREGATE_XML))
    email.extract_attachments

    assert_nil email.dmarc_report
  end

  test "is nil when no attachment is a readable DMARC report" do
    email = create_inbound_email(rcpt_to: "dmarc-reports@example.com", raw: raw_with_report("not xml at all"))
    email.extract_attachments

    assert_nil email.dmarc_report
  end

  test "stops at the first attachment that is a readable DMARC report" do
    email = create_inbound_email(rcpt_to: "dmarc-reports@example.com", raw: raw_with_report(AGGREGATE_XML, AGGREGATE_XML))
    email.extract_attachments
    report = MailReport::Dmarc.parse(AGGREGATE_XML)

    MailReport::Dmarc.expects(:parse).once.returns(report)

    assert_equal report, email.dmarc_report
  end

  private
    AGGREGATE_XML = <<~XML.freeze
      <?xml version="1.0" encoding="UTF-8" ?>
      <feedback>
        <report_metadata>
          <org_name>google.com</org_name>
          <report_id>14054835605949254452</report_id>
          <date_range><begin>1785196800</begin><end>1785283199</end></date_range>
        </report_metadata>
        <policy_published>
          <domain>example.com</domain>
          <p>reject</p>
        </policy_published>
        <record>
          <row>
            <source_ip>203.0.113.9</source_ip>
            <count>42</count>
            <policy_evaluated>
              <disposition>none</disposition>
              <dkim>pass</dkim>
              <spf>pass</spf>
            </policy_evaluated>
          </row>
          <identifiers><header_from>example.com</header_from></identifiers>
        </record>
      </feedback>
    XML

    def raw_with_report(*xmls)
      <<~EOM
        From: noreply-dmarc-support@google.com
        To: dmarc-reports@example.com
        Subject: Report domain: example.com
        Content-Type: multipart/mixed; boundary=MIX

        --MIX
        Content-Type: text/plain

        see attached
        #{xmls.map { |xml| attachment_part(xml) }.join}--MIX--
      EOM
    end

    def attachment_part(xml)
      <<~PART
        --MIX
        Content-Type: application/xml; name="aggregate.xml"
        Content-Disposition: attachment; filename="aggregate.xml"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64(xml)}
      PART
    end
end
