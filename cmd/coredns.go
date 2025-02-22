package main

import (
	"fmt"

	_ "github.com/coredns/coredns/core/plugin"
	_ "github.com/rawmind/k8s_gateway"

	"github.com/coredns/caddy"
	"github.com/coredns/coredns/core/dnsserver"
	"github.com/coredns/coredns/coremain"
)

const pluginName = "k8s_gateway"

var (
	version     = "dev"
	dropPlugins = map[string]struct{}{
		"kubernetes":   struct{}{},
		"k8s_external": struct{}{},
	}
	addPlugins = map[string]struct{}{
		pluginName:  struct{}{},
	}
)

func init() {
	var directives []string

	for name := range addPlugins {
		directives = append(directives, name)
	}

	for _, name := range dnsserver.Directives {
		if _, ok := dropPlugins[name]; ok {
			continue
		}
		directives = append(directives, name)
	}

	dnsserver.Directives = directives
	fmt.Print(directives)
}

func main() {
	// extend CoreDNS version with plugin details
	caddy.AppVersion = fmt.Sprintf("%s+%s-%s", coremain.CoreVersion, pluginName, version)
	coremain.Run()
}
