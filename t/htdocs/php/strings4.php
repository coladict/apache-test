<?php 
setlocale (LC_CTYPE, "C");
echo htmlspecialchars ("<>\"&��\n");
echo htmlentities ("<>\"&��\n");
?>
