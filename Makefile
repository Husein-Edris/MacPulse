.PHONY: test app run install clean

test:
	bash scripts/test.sh

app:
	bash scripts/bundle.sh

run: app
	open dist/MacPulse.app

install: app
	@if [ -w /Applications ]; then \
		rm -rf /Applications/MacPulse.app && cp -R dist/MacPulse.app /Applications/; \
		echo "✓ Installed to /Applications/MacPulse.app"; \
	else \
		mkdir -p ~/Applications && rm -rf ~/Applications/MacPulse.app && cp -R dist/MacPulse.app ~/Applications/; \
		echo "✓ Installed to ~/Applications/MacPulse.app"; \
	fi

clean:
	rm -rf .build dist
