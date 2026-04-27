# Security Policy

Longhorn is a CNCF project deeply committed to safeguarding the security of its products and endeavors to resolve security issues in a timely manner.

We extend our heartfelt thanks to the security researchers and users who diligently report vulnerabilities. Your invaluable contributions enhance our ability to improve our systems and protect the user community.

We review all reported security issues with the Longhorn maintainers and coordinate the corresponding fixes and disclosures. We credit all accepted reports from users and security researchers in our [Security Advisories](https://github.com/longhorn/longhorn/security/advisories).

## Reporting a Vulnerability

> Caution: Do not attempt to test a possible vulnerability or an exploit on systems that you do not have an explicit authorization of its owner.

Please before reporting a vulnerability, make sure it impacts a supported version.

### What types of issue to report

This reporting channel focuses on bugs with potential security impact on Longhorn. If you are unsure, check the types of issues NOT to report below.

### What types of issue NOT to report

Some issues are outside of the scope of this channel, and therefore should not be reported:

- CVEs that were found by CVE scanners (e.g. Trivy, Snyk). Public CVEs do not need to be reported as they are fixed as part of the development process.
- Improvements or questions on the security hardening guides. 
- Issues or bugs that aren't security related. These should be reported as a new [Longhorn issue](https://github.com/longhorn/longhorn/issues).
- Issues with mirrored container images, instead please report them via the security channels of the specific upstream project.
- Issues that are self inflicted and require the user to disable security features or downgrade the security of its environment in order for the vulnerability to be exploited.
- Issues that can only be exploited by the administrator itself (after all, the admin is already a privileged user and implicitly trusted).
- Issues regarding missing HTTP headers or exposure of versions in HTTP headers.
- Vulnerabilities affecting directly a user or customer environment. Such vulnerabilities must be reported directly to the affected user/customer. Be advised that such reports can constitute law infringement under certain jurisdictions.

If going through all the examples above you are still in doubt, please go ahead and use this channel. After all, it's better be safe than sorry.

### Supported Versions

Please review our [support maintenance and terms](https://github.com/longhorn/longhorn/blob/master/README.md) to view the current support lifecycle.

### Reporting a Vulnerability

If any vulnerabilities are found, please report them to [longhorn-security](mailto:longhorn-security@suse.com).

The information contained in your report must be treated as embargoed and must not be shared publicly, unless explicitly agreed with us first. This is to protect the Longhorn users and enable us to follow through our coordinated disclosure process. The information shall be kept embargoed until a fix is released.

#### What information to provide

The information below must be provided in order for the report to be timely and effectively analyzed. Reports that miss the required information might be considered AI generated spam or reviewed with a lower priority.

- Product name and version where the issue was observed. If the issue was observed on the source code, the link to the specific code in GitHub instead.
Description of the problem.
- Type of the issue and impact when exploited.
- Steps to reproduce.
- A valid proof of concept (POC) exploit (only on a valid system that you are authorized to perform such proof). A working POC is now mandatory as a proof of work (POW) to reduce the noise of AI generated low quality reports.
- It's mandatory to inform if AI tools were used to find the issue being reported, to automate or to write the report, POC code or possible patch. If this was the case, then inform which AI tools and models were used.

The more information you provide, the faster we will be able to reproduce the issue and address your concerns more effectively.