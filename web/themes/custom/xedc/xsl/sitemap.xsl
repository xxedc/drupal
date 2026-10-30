<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:sitemap="http://www.sitemaps.org/schemas/sitemap/0.9"
  exclude-result-prefixes="sitemap">
  <xsl:output method="html" encoding="UTF-8" indent="yes"/>

  <xsl:template match="/">
    <html lang="zh-Hans">
      <head>
        <meta charset="utf-8"/>
        <title>DcLili 站点地图</title>
        <style>
          body { margin: 0; padding: 32px 20px 64px; color: #18181b; background: #fff; font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif; }
          main { max-width: 960px; margin: 0 auto; }
          h1 { margin: 0 0 8px; font-size: 28px; font-weight: 700; letter-spacing: -0.03em; }
          .lead { margin: 0 0 24px; color: #71717a; }
          table { width: 100%; border-collapse: collapse; }
          th, td { padding: 10px 12px; border-bottom: 1px solid #e4e4e7; text-align: left; vertical-align: top; }
          th { font-size: 13px; font-weight: 650; color: #71717a; }
          a { color: #18181b; text-decoration: none; word-break: break-all; }
          a:hover { text-decoration: underline; }
          .when { white-space: nowrap; color: #3f3f46; }
        </style>
      </head>
      <body>
        <main>
          <h1>DcLili 站点地图</h1>
          <xsl:choose>
            <xsl:when test="sitemap:urlset">
              <p class="lead">
                共 <xsl:value-of select="count(sitemap:urlset/sitemap:url)"/> 条地址
                <xsl:if test="sitemap:urlset/sitemap:url/sitemap:lastmod">
                  <xsl:text>，更新于 </xsl:text>
                  <xsl:for-each select="sitemap:urlset/sitemap:url/sitemap:lastmod">
                    <xsl:sort select="." order="descending"/>
                    <xsl:if test="position() = 1">
                      <xsl:value-of select="substring(translate(., 'T', ' '), 1, 19)"/>
                    </xsl:if>
                  </xsl:for-each>
                </xsl:if>
              </p>
              <table>
                <thead>
                  <tr>
                    <th>URL</th>
                    <th>最后更新</th>
                  </tr>
                </thead>
                <tbody>
                  <xsl:apply-templates select="sitemap:urlset/sitemap:url"/>
                </tbody>
              </table>
            </xsl:when>
            <xsl:otherwise>
              <p class="lead">
                共 <xsl:value-of select="count(sitemap:sitemapindex/sitemap:sitemap)"/> 份站点地图
                <xsl:if test="sitemap:sitemapindex/sitemap:sitemap/sitemap:lastmod">
                  <xsl:text>，更新于 </xsl:text>
                  <xsl:for-each select="sitemap:sitemapindex/sitemap:sitemap/sitemap:lastmod">
                    <xsl:sort select="." order="descending"/>
                    <xsl:if test="position() = 1">
                      <xsl:value-of select="substring(translate(., 'T', ' '), 1, 19)"/>
                    </xsl:if>
                  </xsl:for-each>
                </xsl:if>
              </p>
              <table>
                <thead>
                  <tr>
                    <th>URL</th>
                    <th>最后更新</th>
                  </tr>
                </thead>
                <tbody>
                  <xsl:apply-templates select="sitemap:sitemapindex/sitemap:sitemap"/>
                </tbody>
              </table>
            </xsl:otherwise>
          </xsl:choose>
        </main>
      </body>
    </html>
  </xsl:template>

  <xsl:template match="sitemap:url|sitemap:sitemap">
    <tr>
      <td>
        <a href="{sitemap:loc}">
          <xsl:value-of select="sitemap:loc"/>
        </a>
      </td>
      <td class="when">
        <xsl:value-of select="sitemap:lastmod"/>
      </td>
    </tr>
  </xsl:template>
</xsl:stylesheet>
