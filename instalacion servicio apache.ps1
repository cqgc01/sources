At line:38 char:63
+ ...       $occupant = Get-Process -Id ($port80.OwningProcess[0] ? $port80 ...
+                                                                 ~
Unexpected token '?' in expression or statement.
At line:38 char:62
+         $occupant = Get-Process -Id ($port80.OwningProcess[0] ? $port ...
+                                                              ~
Missing closing ')' in expression.
At line:36 char:31
+     if ($port80 -or $port443) {
+                               ~
Missing closing '}' in statement block or type definition.
At line:22 char:54
+ if ((Get-Service $serviceName).Status -ne "Running") {
+                                                      ~
Missing closing '}' in statement block or type definition.
At line:38 char:117
+ ... ingProcess[0] ? $port80.OwningProcess[0] : $port443.OwningProcess[0])
+                                                                         ~
Unexpected token ')' in expression or statement.
At line:41 char:5
+     }
+     ~
Unexpected token '}' in expression or statement.
At line:42 char:1
+ } else {
+ ~
Unexpected token '}' in expression or statement.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordException
    + FullyQualifiedErrorId : UnexpectedToken
